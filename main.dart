import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' hide context;
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';

// ---------------------------------------------------------------------------
// ส่วนจัดการตัวแปรระดับ Global (Global Variables)
// ---------------------------------------------------------------------------
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> showAmountNotifier = ValueNotifier(false);
final ValueNotifier<int> currentWalletIdNotifier = ValueNotifier(1); 

// ---------------------------------------------------------------------------
// จุดเริ่มต้นของแอปพลิเคชัน (Main Entry Point)
// ---------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ตรวจสอบและเริ่มต้นระบบฐานข้อมูลสำหรับ Desktop (Windows/Linux)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // เริ่มต้นรูปแบบวันที่ภาษาไทย
  await initializeDateFormatting('th', null);

  // โหลดค่าการตั้งค่าเริ่มต้นจากฐานข้อมูล
  try {
    bool isDark = await DatabaseHelper.instance.getConfig('isDark');
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    bool showAmount = await DatabaseHelper.instance.getConfig('showPieChartAmount');
    showAmountNotifier.value = showAmount;
    
    int lastWallet = await DatabaseHelper.instance.getConfigInt('lastWalletId');
    if (lastWallet != 0) {
      currentWalletIdNotifier.value = lastWallet;
    }
  } catch (e) {
    // กรณีเกิดข้อผิดพลาด ให้ใช้ค่าเริ่มต้น
    themeNotifier.value = ThemeMode.light;
    showAmountNotifier.value = false;
  }

  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// วิดเจ็ตหลักของแอปพลิเคชัน (Root Widget)
// ---------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.indigo,
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
            fontFamily: 'Itim',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            cardColor: Colors.white,
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: ZoomPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            }),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.indigo,
            scaffoldBackgroundColor: const Color(0xFF121212),
            fontFamily: 'Itim',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardColor: const Color(0xFF1E1E1E),
            dialogBackgroundColor: const Color(0xFF1E1E1E),
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: ZoomPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            }),
          ),
          home: const ExpenseTrackerApp(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ส่วนจัดการฐานข้อมูล (Database Helper)
// ---------------------------------------------------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expense_tracker_v2.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(path, version: 1, onCreate: _createDB);
    return db;
  }

  // สร้างตารางฐานข้อมูลเมื่อเปิดใช้งานครั้งแรก
  Future _createDB(Database db, int version) async {
    // ตารางเก็บข้อมูลกระเป๋าเงิน
    await db.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT
      )
    ''');
    
    // ตารางเก็บรายการธุรกรรม (รายรับ-รายจ่าย)
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_id INTEGER,
        type TEXT,
        category TEXT,
        amount REAL,
        date TEXT,
        note TEXT
      )
    ''');

    // ตารางเก็บหมวดหมู่
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        name TEXT,
        icon TEXT
      )
    ''');

    // ตารางเก็บค่าการตั้งค่าต่างๆ
    await db.execute("CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT)");

    await _insertDefaultData(db);
  }

  // เพิ่มข้อมูลเริ่มต้นลงในฐานข้อมูล
  Future<void> _insertDefaultData(Database db) async {
    await db.insert('wallets', {'name': 'กระเป๋าหลัก'});

    Map<String, String> income = {'เงินเดือน': '💰', 'โบนัส': '🎁', 'ขายของ': '🛍️', 'ดอกเบี้ย': '📈'};
    Map<String, String> expense = {'ค่าอาหาร': '🍔', 'ค่าเดินทาง': '🚗', 'ค่าน้ำค่าไฟ': '💡', 'ค่าเช่าห้อง': '🏠', 'ช้อปปิ้ง': '👗'};

    income.forEach((name, icon) async {
      await db.insert('categories', {'type': 'รายรับ', 'name': name, 'icon': icon});
    });
    expense.forEach((name, icon) async {
      await db.insert('categories', {'type': 'รายจ่าย', 'name': name, 'icon': icon});
    });
  }

  // --- ส่วนจัดการค่า Config (Configuration) ---
  Future<void> setConfig(String key, dynamic value) async {
    final db = await instance.database;
    await db.insert('config', {'key': key, 'value': value.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getConfig(String key) async {
    final db = await instance.database;
    final res = await db.query('config', where: "key = ?", whereArgs: [key]);
    if (res.isNotEmpty) return res.first['value'] == 'true';
    return false; 
  }

  Future<int> getConfigInt(String key) async {
    final db = await instance.database;
    final res = await db.query('config', where: "key = ?", whereArgs: [key]);
    if (res.isNotEmpty) return int.tryParse(res.first['value'] as String) ?? 0;
    return 0;
  }

  // ล้างข้อมูลทั้งหมดและเริ่มใหม่ (Factory Reset)
  Future<void> factoryReset() async {
    final db = await instance.database;
    await db.delete('transactions');
    await db.delete('categories');
    await db.delete('wallets');
    await _insertDefaultData(db);
    currentWalletIdNotifier.value = 1;
  }

  // --- ส่วนจัดการกระเป๋าเงิน (Wallet Operations) ---
  Future<List<Map<String, dynamic>>> getWallets() async {
    final db = await instance.database;
    return await db.query('wallets');
  }

  Future<int> addWallet(String name) async {
    final db = await instance.database;
    return await db.insert('wallets', {'name': name});
  }

  Future<int> updateWallet(int id, String name) async {
    final db = await instance.database;
    return await db.update('wallets', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWallet(int id) async {
    final db = await instance.database;
    // ลบรายการธุรกรรมที่ผูกกับกระเป๋านี้ออกด้วย
    await db.delete('transactions', where: 'wallet_id = ?', whereArgs: [id]);
    return await db.delete('wallets', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getWalletName(int id) async {
    final db = await instance.database;
    final res = await db.query('wallets', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first['name'] as String;
    return "ไม่พบกระเป๋า";
  }

  // --- ส่วนจัดการรายการธุรกรรม (Transaction Operations) ---
  Future<List<Map<String, dynamic>>> getTransactionsByMonth(int walletId, int month, int year) async {
    final db = await instance.database;
    String monthStr = month.toString().padLeft(2, '0');
    return await db.query(
      'transactions',
      where: "wallet_id = ? AND strftime('%Y-%m', date) = ?",
      whereArgs: [walletId, '$year-$monthStr'],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllTransactions(int walletId) async {
    final db = await instance.database;
    return await db.query('transactions', where: 'wallet_id = ?', whereArgs: [walletId], orderBy: 'date DESC, id DESC');
  }
  
  // ดึงข้อมูลทั้งหมดเพื่อการส่งออก (Export)
  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT t.*, w.name as wallet_name 
      FROM transactions t
      LEFT JOIN wallets w ON t.wallet_id = w.id
      ORDER BY t.date DESC, t.id DESC
    ''');
  }

  Future<double> getTotalBalance(int walletId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT SUM(CASE WHEN type = 'รายรับ' THEN amount ELSE -amount END) as total FROM transactions WHERE wallet_id = ?",
      [walletId]
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  Future<int> addTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('transactions', row);
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- ส่วนจัดการหมวดหมู่ (Category Operations) ---
  Future<int> addCategory(String type, String name, String icon) async {
    final db = await instance.database;
    final exist = await db.query('categories', where: 'type = ? AND name = ?', whereArgs: [type, name]);
    if (exist.isEmpty) {
      return await db.insert('categories', {'type': type, 'name': name, 'icon': icon});
    }
    return 0;
  }

  Future<int> updateCategory(int id, String name, String icon) async {
    final db = await instance.database;
    return await db.update('categories', {'name': name, 'icon': icon}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCategory(int id) async {
    final db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getCategoriesWithId(String type) async {
    final db = await instance.database;
    return await db.query('categories', where: 'type = ?', whereArgs: [type]);
  }

  Future<Map<String, String>> getCategoryEmojiMap() async {
    final db = await instance.database;
    final result = await db.query('categories');
    Map<String, String> map = {};
    for (var row in result) {
      map[row['name'] as String] = (row['icon'] as String?) ?? '⚪';
    }
    return map;
  }

  Future<List<String>> getCategories(String type) async {
    final db = await instance.database;
    final result = await db.query('categories', where: 'type = ?', whereArgs: [type]);
    return result.map((e) => e['name'] as String).toList();
  }

  // --- ส่วนสำรองและกู้คืนข้อมูล (Backup & Restore) ---
  Future<String> backupData() async {
    final db = await instance.database;
    final transactions = await db.query('transactions');
    final categories = await db.query('categories');
    final wallets = await db.query('wallets');
    
    final Map<String, dynamic> backup = {
      'version': 3, 
      'timestamp': DateTime.now().toIso8601String(),
      'wallets': wallets,
      'categories': categories,
      'transactions': transactions,
    };
    return jsonEncode(backup);
  }

  Future<void> restoreData(String jsonString) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final db = await instance.database;

      await db.transaction((txn) async {
        // ลบข้อมูลเก่าทั้งหมดก่อนนำเข้าข้อมูลใหม่
        await txn.delete('transactions');
        await txn.delete('categories');
        await txn.delete('wallets');

        if (data['wallets'] != null) {
          for (var item in (data['wallets'] as List)) {
            await txn.insert('wallets', item);
          }
        } else {
           await txn.insert('wallets', {'id': 1, 'name': 'กระเป๋าหลัก'});
        }

        if (data['categories'] != null) {
          for (var item in (data['categories'] as List)) {
            await txn.insert('categories', item);
          }
        }

        if (data['transactions'] != null) {
          for (var item in (data['transactions'] as List)) {
            Map<String, dynamic> trans = Map.from(item);
            if (!trans.containsKey('wallet_id')) {
              trans['wallet_id'] = 1;
            }
            await txn.insert('transactions', trans);
          }
        }
      });
    } catch (e) {
      throw Exception("ไฟล์ข้อมูลไม่ถูกต้อง");
    }
  }
}

// ---------------------------------------------------------------------------
// หน้าจอหลักของแอปพลิเคชัน (Main Screen)
// ---------------------------------------------------------------------------
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  
  int _bottomNavIndex = 0; 
  int _viewModeIndex = 0; 
  int _chartTabIndex = 0;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _allHistory = [];
  Map<String, String> _categoryIconMap = {};
  
  double _monthlyIncome = 0;
  double _monthlyExpense = 0;
  double _allTimeBalance = 0;

  List<Map<String, dynamic>> _wallets = [];

  @override
  void initState() {
    super.initState();
    _loadWallets();
    currentWalletIdNotifier.addListener(_refreshData);
    showAmountNotifier.addListener(() { if(mounted) setState((){}); });
  }

  @override
  void dispose() {
    currentWalletIdNotifier.removeListener(_refreshData);
    _pageController.dispose();
    super.dispose();
  }

  void _loadWallets() async {
    final wallets = await DatabaseHelper.instance.getWallets();
    setState(() {
      _wallets = wallets;
    });
    if (!_wallets.any((w) => w['id'] == currentWalletIdNotifier.value)) {
      if (_wallets.isNotEmpty) {
        currentWalletIdNotifier.value = _wallets.first['id'];
        DatabaseHelper.instance.setConfig('lastWalletId', currentWalletIdNotifier.value);
      }
    }
    _refreshData();
  }

  void _refreshData() async {
    int walletId = currentWalletIdNotifier.value;
    final data = await DatabaseHelper.instance.getTransactionsByMonth(walletId, _focusedDay.month, _focusedDay.year);
    final allData = await DatabaseHelper.instance.getAllTransactions(walletId);
    final iconMap = await DatabaseHelper.instance.getCategoryEmojiMap();

    double income = 0;
    double expense = 0;
    for (var item in data) {
      if (item['type'] == 'รายรับ') {
        income += item['amount'];
      } else {
        expense += item['amount'];
      }
    }

    final totalBalance = await DatabaseHelper.instance.getTotalBalance(walletId);

    if (mounted) {
      setState(() {
        _transactions = data;
        _allHistory = allData;
        _categoryIconMap = iconMap;
        _monthlyIncome = income;
        _monthlyExpense = expense;
        _allTimeBalance = totalBalance;
      });
    }
  }

  void _showAddTransactionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        ),
        child: AddTransactionForm(initialDate: _selectedDay),
      ),
    ).then((_) => _refreshData());
  }

  void _onPageChanged(int index) {
    setState(() {
      _viewModeIndex = index;
    });
  }

  void _onTabTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // --- ส่วนสร้างหน้าแสดงภาพรวม (Overview Page) ---
  Widget _buildOverviewPage() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(left: 20, right: 20, bottom: 25, top: MediaQuery.of(context).padding.top + 10),
          decoration: const BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
          ),
          child: Column(
            children: [
              // ส่วนเลือกกระเป๋าเงิน (Wallet Dropdown)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _wallets.any((w) => w['id'] == currentWalletIdNotifier.value) ? currentWalletIdNotifier.value : null,
                      dropdownColor: Colors.indigo.shade700,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Itim'),
                      items: _wallets.map((w) {
                        return DropdownMenuItem<int>(
                          value: w['id'],
                          child: Text(w['name']),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            currentWalletIdNotifier.value = val;
                            DatabaseHelper.instance.setConfig('lastWalletId', val);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              
              const Text("ยอดคงเหลือสุทธิ", style: TextStyle(color: Colors.white70)),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _allTimeBalance),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                builder: (context, value, child) {
                  return Text(
                    "฿${value.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                  );
                },
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(child: _buildHeaderBox('รายรับ (เดือนนี้)', _monthlyIncome, Colors.greenAccent)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildHeaderBox('รายจ่าย (เดือนนี้)', _monthlyExpense, Colors.orangeAccent)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 5)],
          ),
          child: Row(
            children: [
              _buildTabButton("รายเดือน", 0),
              _buildTabButton("รายวัน", 1),
              _buildTabButton("ประวัติ", 2),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: [
              SingleChildScrollView(padding: const EdgeInsets.only(bottom: 30), child: _buildMonthlyContent()),
              SingleChildScrollView(padding: const EdgeInsets.only(bottom: 30), child: _buildDailyContent()),
              SingleChildScrollView(padding: const EdgeInsets.only(bottom: 30), child: _buildHistoryContent()),
            ],
          ),
        ),
      ],
    );
  }

  // --- ส่วนสร้างหน้าเมนู (Menu Page) ---
  Widget _buildMenuPage() {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("เมนู", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FadeInAnimation(delay: 1, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.wallet, color: Colors.orangeAccent)), title: const Text("จัดการกระเป๋าเงิน", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("เพิ่ม/ลบ บัญชีหรือกระเป๋า"), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletManagementScreen())).then((_) => _loadWallets())))),
          const SizedBox(height: 15),

          FadeInAnimation(delay: 2, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.category, color: Colors.indigo)), title: const Text("จัดการหมวดหมู่", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("เพิ่ม/ลบ/แก้ไข รายรับและรายจ่าย"), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CategoryManagementScreen())).then((_) => _refreshData())))),
          const SizedBox(height: 15),
          FadeInAnimation(delay: 3, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.palette, color: Colors.purple)), title: const Text("ธีมแอปพลิเคชัน", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(themeNotifier.value == ThemeMode.light ? "โหมดสว่าง" : "โหมดมืด"), trailing: Switch(value: themeNotifier.value == ThemeMode.dark, onChanged: (val) { setState(() { themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light; DatabaseHelper.instance.setConfig('isDark', val); }); })))),
          const SizedBox(height: 15),
          FadeInAnimation(delay: 4, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.pie_chart, color: Colors.green)), title: const Text("แสดงยอดเงินในกราฟ", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("แสดงจำนวนเงินใน Pie Chart"), trailing: Switch(value: showAmountNotifier.value, onChanged: (val) { setState(() { showAmountNotifier.value = val; DatabaseHelper.instance.setConfig('showPieChartAmount', val); }); })))),
          const SizedBox(height: 15),
          FadeInAnimation(delay: 5, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.calculate, color: Colors.teal)), title: const Text("เครื่องคิดเลข", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("คำนวณเงิน"), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CalculatorScreen()))))),
          const SizedBox(height: 15),
          
          FadeInAnimation(delay: 6, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.table_view, color: Colors.green)), title: const Text("ส่งออก Excel (CSV)", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("แปลงข้อมูลเป็นไฟล์ CSV"), onTap: () => _showExportCSVDialog()))),
          const SizedBox(height: 15),

          FadeInAnimation(delay: 7, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cloud_upload, color: Colors.orange)), title: const Text("สำรองข้อมูล", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Copy ข้อมูลเก็บไว้"), onTap: () => _showBackupDialog()))),
          const SizedBox(height: 15),
          
          FadeInAnimation(delay: 8, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cloud_download, color: Colors.blueAccent)), title: const Text("กู้คืนข้อมูล", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("นำข้อมูลกลับมา"), onTap: () => _showRestoreDialog()))),
          const SizedBox(height: 15),
          
          // ปุ่มแนะนำให้เพื่อน (Recommend to Friends)
          FadeInAnimation(delay: 9, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.pinkAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.share, color: Colors.pinkAccent)), title: const Text("แนะนำให้เพื่อน", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("ชวนเพื่อนมาใช้แอป"), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: () => _showRecommendSheet()))),
          const SizedBox(height: 15),

          FadeInAnimation(delay: 10, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.info_outline, color: Colors.blue)), title: const Text("ข้อมูลเพิ่มเติม", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("ผู้จัดทำ, เวอร์ชัน, อัปเดต"), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutScreen()))))),
          const SizedBox(height: 15),
          FadeInAnimation(delay: 11, child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.restore, color: Colors.red)), title: const Text("ล้างข้อมูลทั้งหมด", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), subtitle: const Text("Factory Reset"), onTap: () => _confirmFactoryReset()))),
        ],
      ),
    );
  }

  // --- ฟังก์ชันแสดงหน้าต่างแนะนำเพื่อน (Share Sheet) ---
  void _showRecommendSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("แนะนำให้เพื่อน", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("ชวนเพื่อนมาจดบันทึกรายรับ-รายจ่ายกันเถอะ!", style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 20),
            
            // แสดงรูปภาพ QR Code
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10)]
              ),
              child: Image.asset(
                'assets/icons/qr.png', 
                width: 150,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 150, height: 150,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.qr_code_2, size: 50, color: Colors.grey),
                        SizedBox(height: 5),
                        Text("ไม่พบรูป QR", style: TextStyle(color: Colors.grey, fontSize: 10))
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 25),
            
            // ปุ่มแชร์โซเชียลมีเดีย
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildShareIconBtn(Icons.chat_bubble, "Line", Colors.green, "Line"),
                _buildShareIconBtn(Icons.facebook, "Facebook", Colors.blue, "Facebook"),
                _buildShareIconBtn(Icons.copy, "คัดลอกลิงก์", Colors.grey, "Copy"),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildShareIconBtn(IconData icon, String label, Color color, String type) {
    return GestureDetector(
      onTap: () {
        // คัดลอกลิงก์ Google Drive ไปยัง Clipboard
        Clipboard.setData(const ClipboardData(text: "https://drive.google.com/drive/folders/1PVHUsHRKy7d-7fEZtiayDjXlvs0vj3oR?usp=sharing"));
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == "Copy" ? "คัดลอกลิงก์แล้ว!" : "คัดลอกลิงก์สำหรับ $label แล้ว!")));
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showExportCSVDialog() async {
    final data = await DatabaseHelper.instance.getAllTransactionsForExport();
    StringBuffer csv = StringBuffer();
    csv.writeln('\uFEFFวันที่,กระเป๋าเงิน,หมวดหมู่,ประเภท,จำนวนเงิน,บันทึก'); 
    for (var item in data) {
      String date = item['date'];
      String wallet = item['wallet_name'] ?? 'ไม่ระบุ';
      String category = item['category'];
      String type = item['type'];
      String amount = item['amount'].toString();
      String note = (item['note'] ?? '').replaceAll(',', ' '); 
      csv.writeln('$date,$wallet,$category,$type,$amount,$note');
    }
    String csvString = csv.toString();
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("ส่งออก CSV (Excel)"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("คัดลอกข้อมูลด้านล่าง แล้วนำไปวางในไฟล์ Text หรือ Note จากนั้นบันทึกเป็นไฟล์นามสกุล .csv เพื่อเปิดใน Excel", style: TextStyle(fontSize: 14)), const SizedBox(height: 15), Container(height: 150, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: SingleChildScrollView(child: Text(csvString, style: const TextStyle(fontSize: 10, color: Colors.black87, fontFamily: 'Courier'))))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ปิด")), ElevatedButton.icon(icon: const Icon(Icons.copy), label: const Text("คัดลอก CSV"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () { Clipboard.setData(ClipboardData(text: csvString)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("คัดลอก CSV เรียบร้อย!"))); Navigator.pop(ctx); })]));
  }

  void _showBackupDialog() async {
    String jsonString = await DatabaseHelper.instance.backupData();
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("สำรองข้อมูล"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("กดปุ่มด้านล่างเพื่อคัดลอกรหัสข้อมูล แล้วนำไปเก็บไว้ในที่ปลอดภัย (เช่น Note)", style: TextStyle(fontSize: 14)), const SizedBox(height: 15), Container(height: 100, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: SingleChildScrollView(child: Text(jsonString, style: const TextStyle(fontSize: 10, color: Colors.black54))))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ปิด")), ElevatedButton.icon(icon: const Icon(Icons.copy), label: const Text("คัดลอก"), onPressed: () { Clipboard.setData(ClipboardData(text: jsonString)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("คัดลอกข้อมูลแล้ว!"))); Navigator.pop(ctx); })]));
  }

  void _showRestoreDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("กู้คืนข้อมูล"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("วางรหัสข้อมูลที่คุณเคยสำรองไว้ที่นี่เพื่อกู้คืน", style: TextStyle(fontSize: 14)), const SizedBox(height: 15), TextField(controller: controller, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "วางรหัส JSON ที่นี่...", hintStyle: TextStyle(fontSize: 12)))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo), onPressed: () async { if (controller.text.isEmpty) return; try { await DatabaseHelper.instance.restoreData(controller.text); if (mounted) { Navigator.pop(ctx); _loadWallets(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("กู้คืนข้อมูลสำเร็จ!"))); } } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ข้อมูลไม่ถูกต้อง!"), backgroundColor: Colors.red)); } } }, child: const Text("กู้คืน", style: TextStyle(color: Colors.white)))]));
  }

  void _confirmFactoryReset() async {
    bool confirm = await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("ยืนยันการคืนค่าข้อมูล"), content: const Text("ข้อมูลทั้งหมดจะหายไป คุณแน่ใจหรือไม่?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ยกเลิก")), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ยืนยันลบ", style: TextStyle(color: Colors.red)))])) ?? false;
    if (confirm) { await DatabaseHelper.instance.factoryReset(); _loadWallets(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ล้างข้อมูลเรียบร้อยแล้ว"))); }
  }

  // --- Widget ย่อยสำหรับการแสดงผล ---
  Widget _buildMonthlyContent() {
    return FadeInAnimation(
      delay: 1,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildCalendarCard(),
          ),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))]),
            child: Column(children: [Container(margin: const EdgeInsets.symmetric(horizontal: 60), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Row(children: [_buildChartTabButton("รายรับ", 0), _buildChartTabButton("รายจ่าย", 1)])), const SizedBox(height: 20), _buildPieChartSection(_chartTabIndex == 0 ? 'รายรับ' : 'รายจ่าย')]),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyContent() {
    double dailyIncome = 0;
    double dailyExpense = 0;
    List<Map<String, dynamic>> dailyTransactions = _transactions.where((t) {
      DateTime tDate = DateTime.parse(t['date']);
      return isSameDay(tDate, _selectedDay);
    }).toList();

    for (var t in dailyTransactions) {
      if (t['type'] == 'รายรับ') {
        dailyIncome += t['amount'];
      } else {
        dailyExpense += t['amount'];
      }
    }

    return Column(children: [
      FadeInAnimation(
        delay: 1,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))]), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("ค่าใช้จ่ายรายวัน", style: TextStyle(color: Colors.grey[600], fontSize: 14)), Text(DateFormat('d MMM', 'th').format(_selectedDay), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo))]), const SizedBox(height: 15), _buildSummaryRow("รายจ่ายวันนี้", "- ${dailyExpense.toStringAsFixed(0)} บาท", Colors.red), const SizedBox(height: 8), _buildSummaryRow("รายรับวันนี้", "+ ${dailyIncome.toStringAsFixed(0)} บาท", Colors.green), const SizedBox(height: 8), _buildSummaryRow("โอนเงินวันนี้", "0 บาท", Colors.grey), const Divider(height: 25), _buildSummaryRow("คงเหลือสุทธิ", "${(dailyIncome - dailyExpense).toStringAsFixed(0)} บาท", Theme.of(context).textTheme.bodyMedium!.color ?? Colors.black, isBold: true)]))),
      ),
      const SizedBox(height: 20),
      FadeInAnimation(
        delay: 2,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))]),
          child: Column(children: [
            Container(margin: const EdgeInsets.symmetric(horizontal: 60), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Row(children: [_buildChartTabButton("รายรับ", 0), _buildChartTabButton("รายจ่าย", 1)])), 
            const SizedBox(height: 20), 
            _buildPieChartSection(_chartTabIndex == 0 ? 'รายรับ' : 'รายจ่าย', sourceData: dailyTransactions)
          ]),
        ),
      ),
    ]);
  }

  Widget _buildHistoryContent() {
    Map<String, List<Map<String, dynamic>>> groupedHistory = {};
    for (var t in _allHistory) {
      String dateKey = t['date'];
      if (!groupedHistory.containsKey(dateKey)) {
        groupedHistory[dateKey] = [];
      }
      groupedHistory[dateKey]!.add(t);
    }

    List<String> sortedDates = groupedHistory.keys.toList()..sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("ประวัติการทำรายการ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              Text("ทั้งหมด ${sortedDates.length} วัน", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_allHistory.isEmpty)
          const Padding(padding: EdgeInsets.all(40.0), child: Center(child: Text("ยังไม่มีประวัติรายการ", style: TextStyle(color: Colors.grey))))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              String dateKey = sortedDates[index];
              List<Map<String, dynamic>> dailyList = groupedHistory[dateKey]!;
              DateTime dateObj = DateTime.parse(dateKey);

              return FadeInAnimation(
                delay: index,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(DateFormat('d MMM yyyy', 'th').format(dateObj), style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13))),
                    ...dailyList.map((item) {
                      final isIncome = item['type'] == 'รายรับ';
                      String icon = _categoryIconMap[item['category']] ?? '⚪';
                      return Dismissible(
                        key: Key(item['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(15)), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                        confirmDismiss: (direction) async { return await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("ยืนยันการลบ"), content: const Text("ต้องการลบรายการนี้ใช่หรือไม่?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ยกเลิก")), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ลบ", style: TextStyle(color: Colors.red)))])); },
                        onDismissed: (direction) async { await DatabaseHelper.instance.deleteTransaction(item['id']); _refreshData(); },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 5)]),
                          child: Row(
                            children: [
                              Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: isIncome ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle), child: Text(icon, style: const TextStyle(fontSize: 20))),
                              const SizedBox(width: 15),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['category'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), if (item['note'] != null && item['note'] != '') Text(item['note'], style: const TextStyle(fontSize: 12, color: Colors.grey))])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text("${isIncome ? '+' : '-'}${item['amount'].toStringAsFixed(0)}", style: TextStyle(color: isIncome ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15))]),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildTabButton(String title, int index) {
    bool isSelected = _viewModeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? const Color(0xFFB8C8A5) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
          child: Text(title, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildHeaderBox(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)), const SizedBox(height: 5), TweenAnimationBuilder<double>(tween: Tween<double>(begin: 0, end: amount), duration: const Duration(milliseconds: 400), curve: Curves.easeOut, builder: (context, value, child) { return Text("฿${value.toStringAsFixed(0)}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)); })]),
    );
  }

  Widget _buildCalendarCard() {
    var lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() { _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1); }); _refreshData(); }), Text(DateFormat('MMMM yyyy', 'th').format(_focusedDay), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)), IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setState(() { _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1); }); _refreshData(); })]), const Divider(), const SizedBox(height: 10), _buildSummaryRow("รอบเดือน", "1 - ${lastDay.day} ${DateFormat('MMM', 'th').format(_focusedDay)}", Colors.grey), const SizedBox(height: 8), _buildSummaryRow("รายจ่ายรวม", "- ${_monthlyExpense.toStringAsFixed(0)} บาท", Colors.red), const SizedBox(height: 8), _buildSummaryRow("รายรับรวม", "+ ${_monthlyIncome.toStringAsFixed(0)} บาท", Colors.green), const SizedBox(height: 8), _buildSummaryRow("คงเหลือ", "${(_monthlyIncome - _monthlyExpense).toStringAsFixed(0)} บาท", Theme.of(context).textTheme.bodyMedium!.color ?? Colors.black, isBold: true)]),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 15, left: 10, right: 10), child: TableCalendar(locale: 'th_TH', firstDay: DateTime(2020), lastDay: DateTime(2030), focusedDay: _focusedDay, currentDay: DateTime.now(), selectedDayPredicate: (day) => isSameDay(_selectedDay, day), headerVisible: false, calendarFormat: CalendarFormat.month, startingDayOfWeek: StartingDayOfWeek.monday, rowHeight: 70, availableGestures: AvailableGestures.none, onDaySelected: (selectedDay, focusedDay) { setState(() { _selectedDay = selectedDay; _focusedDay = focusedDay; }); }, onPageChanged: (focusedDay) { setState(() { _focusedDay = focusedDay; }); _refreshData(); }, calendarBuilders: CalendarBuilders(defaultBuilder: (context, day, focusedDay) => _buildCalendarBlock(day, isSelected: false, isToday: false), selectedBuilder: (context, day, focusedDay) => _buildCalendarBlock(day, isSelected: true, isToday: false), todayBuilder: (context, day, focusedDay) { if (isSameDay(_selectedDay, day)) return _buildCalendarBlock(day, isSelected: true, isToday: true); return _buildCalendarBlock(day, isSelected: false, isToday: true); }, outsideBuilder: (context, day, focusedDay) => Opacity(opacity: 0.3, child: _buildCalendarBlock(day, isSelected: false, isToday: false))))),
        ],
      ),
    );
  }

  Widget _buildCalendarBlock(DateTime day, {required bool isSelected, required bool isToday}) {
    double dayIncome = 0;
    double dayExpense = 0;
    for (var t in _transactions) {
      DateTime tDate = DateTime.parse(t['date']);
      if (isSameDay(tDate, day)) {
        if (t['type'] == 'รายรับ') dayIncome += t['amount'];
        if (t['type'] == 'รายจ่าย') dayExpense += t['amount'];
      }
    }

    Color bgColor = Colors.transparent;
    Color textColor = Theme.of(context).textTheme.bodyMedium!.color ?? Colors.black87;
    BoxBorder? border = Border.all(color: Colors.grey.shade200);

    if (isSelected) {
      bgColor = Colors.orange.shade50;
      border = Border.all(color: Colors.orange.shade200, width: 1.5);
      textColor = Colors.orange[800]!; 
    } else if (isToday) {
      bgColor = Colors.indigo.withValues(alpha: 0.05);
    }

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), border: border),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(padding: const EdgeInsets.only(top: 4, right: 6), child: Align(alignment: Alignment.topRight, child: Text("${day.day}", style: TextStyle(fontSize: 12, fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal, color: textColor)))),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Column(mainAxisSize: MainAxisSize.min, children: [if (dayExpense > 0) Text(dayExpense.toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)), if (dayIncome > 0) Text(dayIncome.toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))])),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)), Text(value, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14))]);
  }

  Widget _buildChartTabButton(String title, int index) {
    bool isSelected = _chartTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _chartTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: isSelected ? Theme.of(context).cardColor : Colors.transparent, borderRadius: BorderRadius.circular(16), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)] : []),
          child: Text(title, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? (index == 0 ? Colors.green : Colors.orange) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  // รองรับการแสดงยอดเงินตามตัวเลือกในเมนู และปรับขนาด
  Widget _buildPieChartSection(String type, {List<Map<String, dynamic>>? sourceData}) {
    List<Map<String, dynamic>> targetData = sourceData ?? _transactions;
    List<Map<String, dynamic>> filteredData = targetData.where((i) => i['type'] == type).toList();
    
    if (filteredData.isEmpty) {
      return Container(height: 200, alignment: Alignment.center, child: const Text("ไม่มีข้อมูล", style: TextStyle(color: Colors.grey)));
    }

    Map<String, double> dataMap = {};
    double totalAmount = 0;
    for (var item in filteredData) {
      dataMap[item['category']] = (dataMap[item['category']] ?? 0) + item['amount'];
      totalAmount += item['amount'];
    }

    var sortedKeys = dataMap.keys.toList()..sort((a, b) => dataMap[b]!.compareTo(dataMap[a]!));

    return ValueListenableBuilder<bool>(
      valueListenable: showAmountNotifier,
      builder: (context, showAmount, child) {
        return Column(
          children: [
            SizedBox(
              height: 220, 
              child: PieChart(
                PieChartData(
                  sections: sortedKeys.map((key) {
                    final value = dataMap[key]!;
                    final baseColor = type == 'รายรับ' ? Colors.green : Colors.orange;
                    final colorIndex = sortedKeys.indexOf(key); 
                    
                    String title = '${(value / totalAmount * 100).toStringAsFixed(0)}%';
                    String icon = _categoryIconMap[key] ?? '';
                    if (icon.isNotEmpty) title = '$icon $title';

                    return PieChartSectionData(
                      color: baseColor.withValues(alpha: (1.0 - (colorIndex * 0.1)).clamp(0.2, 1.0)),
                      value: value,
                      title: title,
                      radius: 75, 
                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // แถบเปอร์เซ็นต์แนวนอน
            ...sortedKeys.map((key) {
              final value = dataMap[key]!;
              final percentage = value / totalAmount;
              final baseColor = type == 'รายรับ' ? Colors.green : Colors.orange;
              final colorIndex = sortedKeys.indexOf(key);
              final color = baseColor.withValues(alpha: (1.0 - (colorIndex * 0.1)).clamp(0.2, 1.0));
              final icon = _categoryIconMap[key] ?? '⚪';

              return Container(
                margin: const EdgeInsets.only(bottom: 12, left: 10, right: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(width: 24, child: Text(icon, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)),
                        const SizedBox(width: 8),
                        Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        Text("${(percentage * 100).toStringAsFixed(1)}%", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        if(showAmount) ...[
                          const SizedBox(width: 8),
                          Text("฿${value.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: color.withValues(alpha: 0.15),
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _bottomNavIndex == 0 ? null : AppBar(title: const Text('My Wallet', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
      body: _bottomNavIndex == 0 ? _buildOverviewPage() : _buildMenuPage(),
      
      // ส่วนแถบนำทางด้านล่าง (Bottom Navigation Bar)
      bottomNavigationBar: Container(
        height: 85 + MediaQuery.of(context).padding.bottom, 
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom), 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, 'assets/icons/overview.png', "ภาพรวม"),
              
              GestureDetector(
                onTap: () => _showAddTransactionModal(context),
                child: Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: Colors.amber[700],
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 32),
                ),
              ),
              
              _buildNavItem(1, 'assets/icons/menu.png', "เมนู"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String assetPath, String label) {
    bool isSelected = _bottomNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _bottomNavIndex = index),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Image.asset(assetPath, width: 24, height: 24), const SizedBox(height: 4), Text(label, style: TextStyle(color: isSelected ? Colors.indigo : Colors.grey, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))]),
    );
  }
}

// ---------------------------------------------------------------------------
// หน้าจัดการกระเป๋าเงิน (Wallet Management Screen)
// ---------------------------------------------------------------------------
class WalletManagementScreen extends StatefulWidget {
  const WalletManagementScreen({super.key});

  @override
  State<WalletManagementScreen> createState() => _WalletManagementScreenState();
}

class _WalletManagementScreenState extends State<WalletManagementScreen> {
  List<Map<String, dynamic>> _wallets = [];

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  void _loadWallets() async {
    final data = await DatabaseHelper.instance.getWallets();
    setState(() {
      _wallets = data;
    });
  }

  void _showAddEditWalletDialog({Map<String, dynamic>? wallet}) {
    final TextEditingController nameController = TextEditingController(text: wallet != null ? wallet['name'] : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(wallet == null ? "เพิ่มกระเป๋าใหม่" : "แก้ไขชื่อกระเป๋า"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "ชื่อกระเป๋า", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                if (wallet == null) {
                  await DatabaseHelper.instance.addWallet(nameController.text);
                } else {
                  await DatabaseHelper.instance.updateWallet(wallet['id'], nameController.text);
                }
                if (mounted) Navigator.pop(ctx);
                _loadWallets();
              }
            },
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );
  }

  void _deleteWallet(int id) async {
    if (_wallets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ต้องมีกระเป๋าอย่างน้อย 1 ใบ")));
      return;
    }
    
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("การลบกระเป๋านี้ จะทำให้ข้อมูลทั้งหมดในกระเป๋านี้หายไปด้วย!"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ยกเลิก")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ลบ", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DatabaseHelper.instance.deleteWallet(id);
      _loadWallets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("จัดการกระเป๋าเงิน"), backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).appBarTheme.foregroundColor, elevation: 0),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _wallets.length,
        separatorBuilder: (ctx, i) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final wallet = _wallets[i];
          return FadeInAnimation(
            delay: i,
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: i == 0 ? const BorderRadius.vertical(top: Radius.circular(12)) : (i == _wallets.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(12)) : null)),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.orangeAccent),
                title: Text(wallet['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showAddEditWalletDialog(wallet: wallet)),
                    if (_wallets.length > 1)
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteWallet(wallet['id'])),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showAddEditWalletDialog(), backgroundColor: Colors.indigo, child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}

// ---------------------------------------------------------------------------
// หน้าจัดการหมวดหมู่ (Category Management Screen)
// ---------------------------------------------------------------------------
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  String _currentType = 'รายจ่าย'; 
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _loadCategories() async {
    final data = await DatabaseHelper.instance.getCategoriesWithId(_currentType);
    setState(() {
      _categories = data;
    });
  }

  void _deleteCategory(int id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("คุณต้องการลบหมวดหมู่นี้ใช่หรือไม่?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ยกเลิก")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ลบ", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DatabaseHelper.instance.deleteCategory(id);
      _loadCategories(); 
    }
  }

  void _showAddCategoryDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emojiController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("เพิ่มหมวดหมู่ ($_currentType)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "ชื่อหมวดหมู่", border: OutlineInputBorder()), autofocus: true),
            const SizedBox(height: 10),
            TextField(controller: emojiController, decoration: const InputDecoration(labelText: "อีโมจิ (เช่น 🍔)", border: OutlineInputBorder(), hintText: "ใส่อีโมจิ 1 ตัว"), maxLength: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                String icon = emojiController.text.isNotEmpty ? emojiController.text : '⚪';
                await DatabaseHelper.instance.addCategory(_currentType, nameController.text, icon);
                if (context.mounted) Navigator.pop(ctx);
                _loadCategories();
              }
            },
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> category) {
    final TextEditingController nameController = TextEditingController(text: category['name']);
    final TextEditingController emojiController = TextEditingController(text: category['icon']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("แก้ไขหมวดหมู่"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "ชื่อหมวดหมู่", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: emojiController, decoration: const InputDecoration(labelText: "อีโมจิ", border: OutlineInputBorder()), maxLength: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                String icon = emojiController.text.isNotEmpty ? emojiController.text : '⚪';
                await DatabaseHelper.instance.updateCategory(category['id'], nameController.text, icon);
                if (context.mounted) Navigator.pop(ctx);
                _loadCategories();
              }
            },
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("จัดการหมวดหมู่"), backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).appBarTheme.foregroundColor, elevation: 0),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [_buildTypeToggle("รายรับ"), _buildTypeToggle("รายจ่าย")]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                return FadeInAnimation(
                  delay: i,
                  child: Container(
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: i == 0 ? const BorderRadius.vertical(top: Radius.circular(12)) : (i == _categories.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(12)) : null)),
                    child: ListTile(
                      leading: Text(cat['icon'] ?? '⚪', style: const TextStyle(fontSize: 24)),
                      title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showEditCategoryDialog(cat)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteCategory(cat['id'])),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddCategoryDialog, backgroundColor: Colors.indigo, child: const Icon(Icons.add, color: Colors.white)),
    );
  }

  Widget _buildTypeToggle(String type) {
    bool isSelected = _currentType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() { _currentType = type; _loadCategories(); }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? Theme.of(context).cardColor : Colors.transparent, borderRadius: BorderRadius.circular(10), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : []),
          child: Text(type, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? (type == 'รายรับ' ? Colors.green : Colors.orange) : Colors.grey)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// หน้าเครื่องคิดเลข (Calculator Screen)
// ---------------------------------------------------------------------------
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _output = "0";
  String _input = "";
  double num1 = 0;
  double num2 = 0;
  String operand = "";

  buttonPressed(String buttonText) {
    if (buttonText == "C") {
      _input = "";
      num1 = 0;
      num2 = 0;
      operand = "";
      _output = "0";
    } else if (buttonText == "⌫") {
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
        if (_input.isEmpty) _output = "0";
      }
    } else if (buttonText == "+" || buttonText == "-" || buttonText == "/" || buttonText == "*") {
      num1 = double.parse(_input.isEmpty ? "0" : _input);
      operand = buttonText;
      _input = "";
    } else if (buttonText == ".") {
      if (_input.contains(".")) {
        return;
      } else {
        _input = _input + buttonText;
      }
    } else if (buttonText == "=") {
      num2 = double.parse(_input.isEmpty ? "0" : _input);
      if (operand == "+") _output = (num1 + num2).toString();
      if (operand == "-") _output = (num1 - num2).toString();
      if (operand == "*") _output = (num1 * num2).toString();
      if (operand == "/") {
        if (num2 != 0) {
          _output = (num1 / num2).toString();
        } else {
          _output = "Error";
        }
      }
      num1 = 0;
      num2 = 0;
      operand = "";
      _input = _output;
    } else {
      _input = _input + buttonText;
    }

    setState(() {
      if (_output.contains(".") && double.tryParse(_output) != null) {
        double temp = double.parse(_output);
        if (temp % 1 == 0) {
          _output = temp.toInt().toString();
        }
      }
      if (_input.isNotEmpty && buttonText != "=" && buttonText != "+" && buttonText != "-" && buttonText != "*" && buttonText != "/" && buttonText != "C" && buttonText != "⌫") {
         _output = _input;
      }
    });
  }

  Widget buildButton(String buttonText, Color color, {Color textColor = Colors.white}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        child: ElevatedButton(
          onPressed: () => buttonPressed(buttonText),
          style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.all(22), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 2),
          child: Text(buttonText, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color displayColor = isDark ? Colors.black26 : Colors.grey[200]!;
    Color btnColor = isDark ? Colors.grey[800]! : Colors.white;
    Color txtColor = isDark ? Colors.white : Colors.black87;
    Color opColor = Colors.orange;

    return Scaffold(
      appBar: AppBar(title: const Text("เครื่องคิดเลข"), elevation: 0),
      body: Column(
        children: <Widget>[
          Container(alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12), color: displayColor, child: Text(_output, style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: txtColor))),
          const Expanded(child: Divider()),
          Column(children: [
            Row(children: [buildButton("C", Colors.redAccent), buildButton("⌫", Colors.blueGrey), buildButton("/", opColor)]),
            Row(children: [buildButton("7", btnColor, textColor: txtColor), buildButton("8", btnColor, textColor: txtColor), buildButton("9", btnColor, textColor: txtColor), buildButton("*", opColor)]),
            Row(children: [buildButton("4", btnColor, textColor: txtColor), buildButton("5", btnColor, textColor: txtColor), buildButton("6", btnColor, textColor: txtColor), buildButton("-", opColor)]),
            Row(children: [buildButton("1", btnColor, textColor: txtColor), buildButton("2", btnColor, textColor: txtColor), buildButton("3", btnColor, textColor: txtColor), buildButton("+", opColor)]),
            Row(children: [buildButton(".", btnColor, textColor: txtColor), buildButton("0", btnColor, textColor: txtColor), buildButton("=", Colors.green)]),
          ])
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// หน้าคำถามที่พบบ่อย (FAQ Screen)
// ---------------------------------------------------------------------------
class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("คำถามที่พบบ่อย"), elevation: 0, backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).appBarTheme.foregroundColor),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ExpansionTile(title: Text("วิธีสำรองข้อมูล", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("ไปที่ เมนู > สำรองข้อมูล แล้วกดปุ่ม คัดลอก เพื่อก็อปปี้รหัสข้อมูลทั้งหมดไปเก็บไว้ในแอป Note หรือส่งเข้า Line Keep"))]),
          ExpansionTile(title: Text("วิธีกู้คืนข้อมูล", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("ไปที่ เมนู > กู้คืนข้อมูล แล้ววางรหัสข้อมูลที่เคยสำรองไว้ลงในช่องว่าง จากนั้นกดปุ่ม กู้คืน"))]),
          ExpansionTile(title: Text("วิธีส่งออกเป็น Excel", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("ไปที่ เมนู > ส่งออก Excel (CSV) แล้วกด คัดลอก นำไปวางในไฟล์ Text แล้วเปลี่ยนนามสกุลเป็น .csv เพื่อเปิดใน Excel"))]),
          ExpansionTile(title: Text("วิธีลบกระเป๋าเงิน", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("ไปที่ เมนู > จัดการกระเป๋าเงิน > กดรูปถังขยะด้านหลังกระเป๋าที่ต้องการลบ (ต้องมีกระเป๋าเหลืออย่างน้อย 1 ใบ)"))]),
          ExpansionTile(title: Text("ข้อมูลจะหายไหมถ้าลบแอป", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("ใช่ ข้อมูลจะหายทั้งหมด ดังนั้นควรหมั่นสำรองข้อมูลเก็บไว้นอกเครื่องบ่อยๆ"))]),
          ExpansionTile(title: Text("แอปเก็บข้อมูลได้เท่าไหร่", style: TextStyle(fontWeight: FontWeight.bold)), children: [Padding(padding: EdgeInsets.all(16.0), child: Text("คำตอบคือ เก็บได้เยอะมหาศาลแทบจะไม่มีวันเต็ม ข้อมูลกินพื้นที่น้อยมาก คุณบันทึกวันละ 10 รายการ ทุกวัน เป็นเวลา 10 ปี (รวม 36,500 รายการ) ไฟล์ฐานข้อมูลอาจจะมีขนาดแค่ประมาณ 5-10 MB เท่านั้น(รูปถ่าย 1 รูปยังกินที่เยอะกว่า)"))]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// หน้าข้อมูลเพิ่มเติม (About Screen)
// ---------------------------------------------------------------------------
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("ข้อมูลเพิ่มเติม"), elevation: 0, backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).appBarTheme.foregroundColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))]), child: ClipOval(child: Image.asset('assets/icons/icon.png', fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) { return Container(color: Colors.orange.shade100, child: const Icon(Icons.account_balance_wallet, size: 50, color: Colors.orange)); }))),
            const SizedBox(height: 15),
            const Text("มีตังค์มั้ย", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("บันทึกรายรับ-รายจ่าย", style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: const Text("เวอร์ชัน 3.3.2", style: TextStyle(fontSize: 12, color: Colors.grey))),
            const SizedBox(height: 30),
            _buildInfoTile(context, "ผู้จัดทำ: นายศิวพงษ์ และ นายทรงพล"),
            const SizedBox(height: 10),
            _buildInfoTile(context, "คำถามที่พบบ่อย (FAQ)", onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const FAQScreen())); }),
            const SizedBox(height: 30),
            Align(alignment: Alignment.centerLeft, child: Text("มีอะไรใหม่!!!!!!!!!!!!!", style: TextStyle(color: Colors.grey[600], fontSize: 14))),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("[2026-02-13] ล่าสุด (v3.3.2)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- ใหม่: เพิ่มปุ่ม 'แนะนำให้เพื่อน' พร้อม QR Code"),
                  Text("- ใหม่: เพิ่มเมนูคำถามที่พบบ่อย (FAQ)"),
                  Text("- ใหญ่: เพิ่มระบบหลายกระเป๋าเงิน (Multi-Wallet)"),
                  Text("- ใหม่: เพิ่มเมนูจัดการกระเป๋าเงิน"),
                  Text("- ใหม่: เลือกกระเป๋าที่จะบันทึกได้"),
                  Text("- ใหม่: เพิ่มปุ่มส่งออกข้อมูลเป็นไฟล์ Excel (CSV)"),
                  Text("- ใหม่: เพิ่มปุ่มแก้ไขหมวดหมู่ (เปลี่ยนชื่อ/อีโมจิได้)"),
                  Text("- เพิ่ม: ระบบสำรองและกู้คืนข้อมูล (Backup & Restore)"),
                  Text("- เพิ่ม: คัดลอกข้อมูลเป็น Text เพื่อเก็บไว้ใน Note"),
                  SizedBox(height: 20),

                  Text("[2026-02-08] (v3.2.0)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- ใหม่: เพิ่ม Emoji ให้กับหมวดหมู่ได้แล้ว!"),
                  Text("- ใหม่: แสดง Emoji ในกราฟและรายการสรุป"),
                  Text("- ปรับปรุง: แก้ไข Layout ให้รองรับแถบสถานะด้านบน"),
                  SizedBox(height: 20),

                  Text("[2026-02-06] (v3.1.4)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- ปรับปรุง: เพิ่มแถบเปอร์เซ็นต์แนวนอนใต้กราฟ"),
                  Text("- ปรับปรุง: เพิ่มตัวเลือกแสดงยอดเงิน (เปิดได้ในเมนู)"),
                  SizedBox(height: 20),

                  Text("[2026-01-29] (v3.1.2)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- เพิ่ม: กราฟวงกลมแสดงสรุปรายรับ-รายจ่ายรายวัน"),
                  SizedBox(height: 20),

                  Text("[2026-01-28] (v3.1.1)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- เพิ่ม: เครื่องคิดเลขในเมนู"),
                  Text("- ปรับปรุง: เปลี่ยนปุ่มเพิ่มรายการกลับเป็นไอคอน +"),
                  Text("- ปรับปรุง: ปิดการเลื่อนสไลด์ที่ปฏิทิน"),
                  Text("- ปรับปรุง: เพิ่มความเร็วอนิเมชั่นให้ลื่นไหลขึ้น"),
                  SizedBox(height: 20),

                  Text("[2026-01-21]", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Text("- เพิ่ม: ระบบจัดการหมวดหมู่ (เพิ่ม/ลบ)"),
                  Text("- เพิ่ม: ระบบเปลี่ยนธีม (Light/Dark Mode)"),
                  Text("- เพิ่ม: ระบบล้างข้อมูล (Factory Reset)"),
                  Text("- เพิ่ม: ระบบดูรายพร้อมสรุปยอดรายรับ-รายจ่ายของแต่ละวัน"),
                  Text("- เพิ่ม: ระบบปฏิทินแสดงภาพรวมรายรับ-รายจ่ายในแต่ละวัน"),
                  Text("- เพิ่ม: เปลี่ยนฟ้อนต์หลักเป็น itim"),
                  Text("- เพิ่ม: เปลี่ยนหน้าประวัติรายการเป็นแบบ Dismissible ลบรายการด้วยการปัดซ้าย ดูสะอาดตาและใช้งานง่ายขึ้น"),
                  Text("- เพิ่ม: navigator ใหม่สำหรับการนำทางภายในแอป"),
                  Text("- เพิ่ม: หน้าข้อมูลเพิ่มเติมและผู้จัดทำ"),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, String title, {VoidCallback? onTap}) {
    return Container(margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)), child: ListTile(title: Text(title, style: const TextStyle(fontSize: 14)), onTap: onTap ?? () {}, trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)));
  }
}

// ---------------------------------------------------------------------------
// ฟอร์มเพิ่มข้อมูลธุรกรรม (Add Transaction Form)
// ---------------------------------------------------------------------------
class AddTransactionForm extends StatefulWidget {
  final DateTime? initialDate;
  const AddTransactionForm({super.key, this.initialDate});

  @override
  State<AddTransactionForm> createState() => _AddTransactionFormState();
}

class _AddTransactionFormState extends State<AddTransactionForm> {
  String _type = 'รายรับ';
  String? _category;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _date;
  List<String> _categories = [];
  
  // ตัวเลือกกระเป๋า
  int _selectedWalletId = currentWalletIdNotifier.value; 
  List<Map<String, dynamic>> _wallets = [];

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
    _loadData();
  }

  void _loadData() async {
    final cats = await DatabaseHelper.instance.getCategories(_type);
    final wallets = await DatabaseHelper.instance.getWallets();
    setState(() {
      _categories = cats;
      if (_category == null || !_categories.contains(_category)) {
        _category = _categories.isNotEmpty ? _categories[0] : null;
      }
      _wallets = wallets;
      // ตรวจสอบว่ากระเป๋าที่เลือกยังมีอยู่ไหม
      if (!_wallets.any((w) => w['id'] == _selectedWalletId)) {
        if (_wallets.isNotEmpty) _selectedWalletId = _wallets.first['id'];
      }
    });
  }

  void _loadCategoriesOnly() async {
    final cats = await DatabaseHelper.instance.getCategories(_type);
    setState(() {
      _categories = cats;
      if (_category == null || !_categories.contains(_category)) {
        _category = _categories.isNotEmpty ? _categories[0] : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            const Text("เพิ่มรายการใหม่", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Dropdown เลือกกระเป๋าที่จะบันทึก
            DropdownButtonFormField<int>(
              value: _selectedWalletId,
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text(w['name']))).toList(),
              onChanged: (val) => setState(() => _selectedWalletId = val!),
              decoration: InputDecoration(labelText: "เลือกกระเป๋าเงิน", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.account_balance_wallet_outlined)),
            ),
            const SizedBox(height: 15),

            Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)), child: Row(children: [_buildTypeButton("รายรับ", Colors.green), _buildTypeButton("รายจ่าย", Colors.orange)])),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(value: _category, items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (val) => setState(() => _category = val), decoration: InputDecoration(labelText: "หมวดหมู่", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.category_outlined))),
            const SizedBox(height: 15),
            TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), decoration: InputDecoration(labelText: "จำนวนเงิน (บาท)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.attach_money))),
            const SizedBox(height: 15),
            InkWell(onTap: () async { final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2030)); if (picked != null) setState(() => _date = picked); }, child: InputDecorator(decoration: InputDecoration(labelText: "วันที่", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.calendar_today)), child: Text(DateFormat('yyyy-MM-dd').format(_date)))),
            const SizedBox(height: 15),
            TextField(controller: _noteController, decoration: InputDecoration(labelText: "บันทึกช่วยจำ (ถ้ามี)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.note_alt_outlined))),
            const SizedBox(height: 25),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async { if (_amountController.text.isEmpty) return; await DatabaseHelper.instance.addTransaction({'wallet_id': _selectedWalletId, 'type': _type, 'category': _category ?? 'อื่นๆ', 'amount': double.tryParse(_amountController.text) ?? 0.0, 'date': DateFormat('yyyy-MM-dd').format(_date), 'note': _noteController.text}); if (context.mounted) Navigator.pop(context); }, child: const Text("บันทึกข้อมูล", style: TextStyle(fontSize: 18, color: Colors.white)))),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(String type, Color color) {
    final isSelected = _type == type;
    return Expanded(child: GestureDetector(onTap: () => setState(() { _type = type; _loadCategoriesOnly(); }), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)] : []), child: Text(type, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? color : Colors.grey)))));
  }
}

// ---------------------------------------------------------------------------
// คลาสสำหรับแอนิเมชัน Fade-in (FadeInAnimation Class)
// ---------------------------------------------------------------------------
class FadeInAnimation extends StatefulWidget {
  final Widget child;
  final int delay;

  const FadeInAnimation({super.key, required this.child, this.delay = 0});

  @override
  State<FadeInAnimation> createState() => _FadeInAnimationState();
}

class _FadeInAnimationState extends State<FadeInAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.delay * 100), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}