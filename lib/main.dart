import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async'; // 匯入 Timer

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 隱藏右上角的 Debug 標籤
      title: 'Hello World Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true, // 使用最新的 Material Design 3 風格
      ),
      home: const MyFormPage(),
    );
  }
}

class MyFormPage extends StatefulWidget {
  const MyFormPage({super.key});

  @override
  State<MyFormPage> createState() => _MyFormPageState();
}

class _MyFormPageState extends State<MyFormPage> {
  // 建立一個 GlobalKey 來識別這個 Form
  final _formKey = GlobalKey<FormState>();

  // 新增一個 List 來儲存 MEMO
  final List<String> _memo = [];

  // 新增一個變數來儲存顯示的時間文字
  String _timeMessage = '';

  // 新增一個布林值來控制 Checkbox
  bool _isAutoRecording = false;

  // 新增一個 Timer
  Timer? _autoRecordTimer;

  @override
  void dispose() {
    // 在 widget 被銷毀時取消計時器，避免 memory leak
    _autoRecordTimer?.cancel();
    super.dispose();
  }

  // 修改方法以記錄當前位置
  Future<void> _recordLocation({bool showSnackBar = true}) async {
    // 檢查定位服務是否啟用
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('請開啟定位服務')));
      }
      return;
    }

    // 檢查並請求權限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted && showSnackBar) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('您已拒絕定位權限')));
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位權限已被永久拒絕，請至設定中開啟')));
      }
      return;
    }

    // 取得目前位置
    final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    final String locationData =
        '經度: ${position.longitude.toStringAsFixed(4)}, 緯度: ${position.latitude.toStringAsFixed(4)}\n'
        '方向: ${position.heading.toStringAsFixed(2)}°, 衛星時間: ${position.timestamp}';

    // 使用 setState 更新狀態，讓畫面重繪
    setState(() {
      _timeMessage = '最後紀錄時間：${DateTime.now().toLocal()}';
      _memo.insert(0, locationData); // 將新位置資訊插入到 MEMO 列表的開頭
    });

    // 顯示底部的 Snackbar 訊息提示
    if (mounted && showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('目前位置已記錄!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // 新增一個方法來清空 MEMO
  void _clearMemo() {
    setState(() {
      _memo.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MEMO 已清空!'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('衛星定位記錄器'), // 1. 更改 AppBar 標題
        backgroundColor: Colors.indigo, // 1. 更改 AppBar 背景顏色
        foregroundColor: Colors.white, // 讓 AppBar 標題變成白色
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                const Text('請點擊下方的按鈕：', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
                // 3. 將 Checkbox 移到按鈕上方
                CheckboxListTile(
                  title: const Text('每秒自動記錄'),
                  value: _isAutoRecording,
                  onChanged: (bool? value) {
                    setState(() {
                      _isAutoRecording = value ?? false;
                      if (_isAutoRecording) {
                        // 開始計時器，每秒執行一次
                        _autoRecordTimer = Timer.periodic(
                            const Duration(seconds: 1), (timer) { // 將更新間隔改為 3 秒
                          _recordLocation(showSnackBar: false);
                        });
                      } else {
                        // 取消計時器
                        _autoRecordTimer?.cancel();
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _recordLocation,
                  icon: const Icon(Icons.location_on),
                  label: const Text('紀錄當前位置', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, // 2. 更改按鈕背景顏色
                    foregroundColor: Colors.white, // 2. 更改按鈕文字和圖示顏色
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 這是新增的 Text 元件，用來顯示時間
                Text(
                  _timeMessage,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'MEMO',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    OutlinedButton.icon(
                      onPressed: _memo.isEmpty ? null : _clearMemo, // 如果 MEMO 是空的，則禁用按鈕
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清空'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: _memo.isEmpty
                        ? const Center(child: Text('目前沒有任何記錄'))
                        : ListView.builder(
                            itemCount: _memo.length,
                            itemBuilder: (context, index) {
                              return ListTile(
                                leading: Text('${_memo.length - index}.'),
                                title: Text(
                                  _memo[index],
                                  style: const TextStyle(fontSize: 15, color: Colors.black87), // 4. 調整 MEMO 列表文字樣式
                                ),
                                dense: true,
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
