import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' hide context;
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ExpenseTrackerApp(),
    themeMode: ThemeMode.light,
  ));
}

// --- ส่วนจัดการฐานข้อมูล (Database Helper) ---
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expense_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        category TEXT,
        amount REAL,
        date TEXT,
        note TEXT
      )
    ''');
    
    // 🔥 OPTIMIZATION 1: สร้าง Index ที่วันที่ เพื่อให้ค้นหาข้อมูลเร็วขึ้น
    await db.execute('CREATE INDEX index_date ON transactions(date)');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        name TEXT
      )
    ''');

    List<String> income = ['เงินเดือน', 'โบนัส', 'ขายของ', 'ดอกเบี้ย', 'อื่นๆ'];
    List<String> expense = ['ค่าอาหาร', 'ค่าเดินทาง', 'ค่าน้ำค่าไฟ', 'ค่าเช่าห้อง', 'ช้อปปิ้ง', 'อื่นๆ'];

    for (var cat in income) {
      await db.insert('categories', {'type': 'รายรับ', 'name': cat});
    }
    for (var cat in expense) {
      await db.insert('categories', {'type': 'รายจ่าย', 'name': cat});
    }
  }

  Future<int> addTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('transactions', row);
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addCategory(String type, String name) async {
    final db = await instance.database;
    final exist = await db.query('categories', where: 'type = ? AND name = ?', whereArgs: [type, name]);
    if (exist.isEmpty) {
      return await db.insert('categories', {'type': type, 'name': name});
    }
    return 0; 
  }

  Future<List<Map<String, dynamic>>> getTransactionsByMonth(int month, int year) async {
    final db = await instance.database;
    String monthStr = month.toString().padLeft(2, '0');
    return await db.query(
      'transactions',
      where: "strftime('%Y-%m', date) = ?",
      whereArgs: ['$year-$monthStr'],
      orderBy: 'date DESC, id DESC', 
    );
  }

  Future<List<String>> getCategories(String type) async {
    final db = await instance.database;
    final result = await db.query('categories', where: 'type = ?', whereArgs: [type]);
    return result.map((e) => e['name'] as String).toList();
  }
}

// --- หน้าจอหลัก (UI) ---
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> with SingleTickerProviderStateMixin {
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> _transactions = [];
  double _totalIncome = 0;
  double _totalExpense = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshData();
  }

  void _refreshData() async {
    final data = await DatabaseHelper.instance.getTransactionsByMonth(selectedDate.month, selectedDate.year);
    
    double income = 0;
    double expense = 0;
    
    for (var item in data) {
      if (item['type'] == 'รายรับ') {
        income += item['amount'];
      } else {
        expense += item['amount'];
      }
    }

    setState(() {
      _transactions = data;
      _totalIncome = income;
      _totalExpense = expense;
    });
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ยืนยันการลบ"), // 🔥 const
        content: const Text("คุณต้องการลบรายการนี้ใช่หรือไม่?"), // 🔥 const
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ยกเลิก", style: TextStyle(color: Colors.grey)), // 🔥 const
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.deleteTransaction(id);
              if (mounted) {
                Navigator.pop(ctx);
                _refreshData();
              }
            },
            child: const Text("ลบ", style: TextStyle(color: Colors.white)), // 🔥 const
          ),
        ],
      ),
    );
  }

  void _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
      helpText: "เลือกเดือนและปี",
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Wallet', style: TextStyle(fontWeight: FontWeight.bold)), // 🔥 const
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month), // 🔥 const
            onPressed: () => _selectMonth(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 10), // 🔥 const
            decoration: const BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(selectedDate),
                  style: const TextStyle(color: Colors.white70, fontSize: 16), // 🔥 const
                ),
                const SizedBox(height: 5), // 🔥 const
                Text(
                  "฿${(_totalIncome - _totalExpense).toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ), // 🔥 const
                ),
                const Text("ยอดคงเหลือสุทธิ", style: TextStyle(color: Colors.white70)), // 🔥 const
                const SizedBox(height: 20), // 🔥 const
                Row(
                  children: [
                    Expanded(child: _buildSummaryBox('รายรับ', _totalIncome, Colors.greenAccent)),
                    const SizedBox(width: 15), // 🔥 const
                    Expanded(child: _buildSummaryBox('รายจ่าย', _totalExpense, Colors.orangeAccent)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10), // 🔥 const

          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo,
              tabs: const [
                Tab(text: "กราฟรายจ่าย"), // 🔥 const
                Tab(text: "กราฟรายรับ"), // 🔥 const
              ],
            ),
          ),
          
          SizedBox(
            height: 220, 
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPieChartPage('รายจ่าย'),
                _buildPieChartPage('รายรับ'),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 5), // 🔥 const
            child: Align(
              alignment: Alignment.centerLeft, 
              child: Text("รายการล่าสุด", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)) // 🔥 const
            ),
          ),

          Expanded(
            child: _transactions.isEmpty 
            ? const Center(child: Text("ยังไม่มีรายการในเดือนนี้", style: TextStyle(color: Colors.grey))) // 🔥 const
            : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16), // 🔥 const
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final item = _transactions[index];
                final isIncome = item['type'] == 'รายรับ';
                
                return Dismissible(
                  key: Key(item['id'].toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6), // 🔥 const
                    decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20), // 🔥 const
                    child: const Icon(Icons.delete, color: Colors.white), // 🔥 const
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("ยืนยันการลบ"), // 🔥 const
                        content: const Text("คุณต้องการลบรายการนี้ใช่หรือไม่?"), // 🔥 const
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("ยกเลิก")), // 🔥 const
                          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("ลบ", style: TextStyle(color: Colors.red))), // 🔥 const
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) async {
                    await DatabaseHelper.instance.deleteTransaction(item['id']);
                    _refreshData();
                  },
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.symmetric(vertical: 6), // 🔥 const
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), // 🔥 const
                      leading: Container(
                        padding: const EdgeInsets.all(10), // 🔥 const
                        decoration: BoxDecoration(
                          color: isIncome ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: isIncome ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(item['category'], style: const TextStyle(fontWeight: FontWeight.bold)), // 🔥 const
                      subtitle: Text(
                        "${item['date']} ${item['note'] != '' ? '• ${item['note']}' : ''}",
                        style: const TextStyle(fontSize: 12), // 🔥 const
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${isIncome ? '+' : '-'}${item['amount'].toStringAsFixed(2)}",
                            style: TextStyle(
                              color: isIncome ? Colors.green[700] : Colors.red[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8), // 🔥 const
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.grey), // 🔥 const
                            onPressed: () => _confirmDelete(item['id']),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(), // 🔥 const
                            tooltip: "ลบรายการ",
                          ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransactionModal(context),
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add), // 🔥 const
        label: const Text("เพิ่มรายการ"), // 🔥 const
      ),
    );
  }

  Widget _buildSummaryBox(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12), // 🔥 const
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)), // 🔥 const
          const SizedBox(height: 4), // 🔥 const
          Text(
            "฿${amount.toStringAsFixed(0)}",
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChartPage(String type) {
    List<Map<String, dynamic>> filteredData = _transactions.where((i) => i['type'] == type).toList();
    
    if (filteredData.isEmpty) {
      return Center(child: Text("ไม่มีข้อมูล$type", style: const TextStyle(color: Colors.grey))); // 🔥 const
    }

    Map<String, double> dataMap = {};
    for (var item in filteredData) {
      dataMap[item['category']] = (dataMap[item['category']] ?? 0) + item['amount'];
    }

    return PieChart(
      PieChartData(
        sections: dataMap.entries.map((e) {
          final isIncome = type == 'รายรับ';
          final baseColor = isIncome ? Colors.green : Colors.orange;
          final colorIndex = dataMap.keys.toList().indexOf(e.key);
          
          return PieChartSectionData(
            color: baseColor.withOpacity(1.0 - (colorIndex * 0.1).clamp(0.0, 0.5)),
            value: e.value,
            title: '${e.key}\n${e.value.toStringAsFixed(0)}',
            radius: 60,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white), // 🔥 const
            titlePositionPercentageOffset: 0.55,
          );
        }).toList(),
        centerSpaceRadius: 30,
        sectionsSpace: 2,
        borderData: FlBorderData(show: false),
      ),
    );
  }

  void _showAddTransactionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        ),
        child: const AddTransactionForm(),
      ),
    ).then((_) => _refreshData());
  }
}

// --- ฟอร์มเพิ่มข้อมูล ---
class AddTransactionForm extends StatefulWidget {
  const AddTransactionForm({super.key});

  @override
  State<AddTransactionForm> createState() => _AddTransactionFormState();
}

class _AddTransactionFormState extends State<AddTransactionForm> {
  String _type = 'รายจ่าย';
  String? _category;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _loadCategories() async {
    final cats = await DatabaseHelper.instance.getCategories(_type);
    setState(() {
      _categories = cats;
      if (_category == null || !_categories.contains(_category)) {
        _category = _categories.isNotEmpty ? _categories[0] : null;
      }
    });
  }

  void _showAddCategoryDialog(BuildContext context) {
    final TextEditingController newCatController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("เพิ่มหมวดหมู่ ($_type)"),
        content: TextField(
          controller: newCatController,
          decoration: const InputDecoration(hintText: "ชื่อหมวดหมู่ใหม่ เช่น 'ค่าเน็ต'"), // 🔥 const
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")), // 🔥 const
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () async {
              if (newCatController.text.isNotEmpty) {
                await DatabaseHelper.instance.addCategory(_type, newCatController.text);
                if (mounted) {
                  _loadCategories();
                  setState(() {
                    _category = newCatController.text;
                  });
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text("บันทึก"), // 🔥 const
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20), // 🔥 const
            const Text("เพิ่มรายการใหม่", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), // 🔥 const
            const SizedBox(height: 20), // 🔥 const
            
            Container(
              padding: const EdgeInsets.all(4), // 🔥 const
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15)),
              child: Row(
                children: [
                  _buildTypeButton("รายจ่าย", Colors.orange),
                  _buildTypeButton("รายรับ", Colors.green),
                ],
              ),
            ),
            const SizedBox(height: 15), // 🔥 const

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _category,
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => _category = val),
                    decoration: InputDecoration(
                      labelText: "หมวดหมู่",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.category_outlined), // 🔥 const
                    ),
                  ),
                ),
                const SizedBox(width: 10), // 🔥 const
                Container(
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.indigo), // 🔥 const
                    onPressed: () => _showAddCategoryDialog(context),
                    tooltip: "เพิ่มหมวดหมู่",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15), // 🔥 const

            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // 🔥 const
              decoration: InputDecoration(
                labelText: "จำนวนเงิน (บาท)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.attach_money), // 🔥 const
              ),
            ),
            const SizedBox(height: 15), // 🔥 const

            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context, 
                  initialDate: _date, 
                  firstDate: DateTime(2000), 
                  lastDate: DateTime(2030)
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: "วันที่",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.calendar_today), // 🔥 const
                ),
                child: Text(DateFormat('yyyy-MM-dd').format(_date)),
              ),
            ),
            const SizedBox(height: 15), // 🔥 const

            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: "บันทึกช่วยจำ (ถ้ามี)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.note_alt_outlined), // 🔥 const
              ),
            ),
            
            const SizedBox(height: 25), // 🔥 const
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (_amountController.text.isEmpty) return;
                  
                  await DatabaseHelper.instance.addTransaction({
                    'type': _type,
                    'category': _category ?? 'อื่นๆ',
                    'amount': double.tryParse(_amountController.text) ?? 0.0,
                    'date': DateFormat('yyyy-MM-dd').format(_date),
                    'note': _noteController.text,
                  });
                  
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("บันทึกข้อมูล", style: TextStyle(fontSize: 18, color: Colors.white)), // 🔥 const
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(String type, Color color) {
    final isSelected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _type = type; _loadCategories(); }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12), // 🔥 const
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : [],
          ),
          child: Text(
            type,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? color : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}