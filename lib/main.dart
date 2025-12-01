import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 先啟動 UI，背景服務稍後初始化
  runApp(const MyApp());
  
  // 在背景初始化服務，避免阻塞 UI
  initializeService().catchError((e) {
    debugPrint('背景服務初始化失敗: $e');
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'gps_location_tracking',
      initialNotificationTitle: '衛星定位記錄器',
      initialNotificationContent: '點擊開啟應用程式',
      foregroundServiceNotificationId: 888,
    ),
  );
}

// iOS 背景執行的進入點
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// 背景服務的進入點
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 每秒記錄一次位置
  int recordCount = 0;
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // 檢查定位服務是否啟用
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          service.invoke('update', {
            "current_date": DateTime.now().toIso8601String(),
            "location_data": "錯誤：定位服務未啟用",
            "status": "error",
          });
          return;
        }

        // 檢查權限
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          service.invoke('update', {
            "current_date": DateTime.now().toIso8601String(),
            "location_data": "錯誤：沒有定位權限",
            "status": "error",
          });
          return;
        }

        try {
          // 取得目前位置
          final Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).timeout(const Duration(seconds: 5));

          recordCount++;
          final String locationData =
              '經度: ${position.longitude.toStringAsFixed(6)}, 緯度: ${position.latitude.toStringAsFixed(6)}\n'
              '高度: ${position.altitude.toStringAsFixed(1)}m, 精度: ${position.accuracy.toStringAsFixed(1)}m\n'
              '方向: ${position.heading.toStringAsFixed(1)}°, 速度: ${position.speed.toStringAsFixed(1)}m/s';

          // 更新通知內容
          service.invoke('update', {
            "current_date": DateTime.now().toIso8601String(),
            "location_data": locationData,
            "record_count": recordCount,
            "status": "success",
          });

          // 更新前景服務通知
          service.setForegroundNotificationInfo(
            title: "衛星定位記錄器",
            content: "已記錄 $recordCount 筆資料 - 最新位置: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}",
          );
        } catch (e) {
          service.invoke('update', {
            "current_date": DateTime.now().toIso8601String(),
            "location_data": "錯誤：無法取得位置 - $e",
            "status": "error",
          });
        }
      }
    }
  });
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
  
  bool _isInitialized = false;
  int _recordCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    try {
      // 監聽來自背景服務的數據更新
      FlutterBackgroundService().on('update').listen((data) {
        if (data != null && mounted) {
          setState(() {
            _timeMessage = '最後紀錄時間：${DateTime.parse(data["current_date"] as String).toLocal()}';
            final locationData = data["location_data"] as String;
            _memo.insert(0, locationData);
            
            if (data.containsKey('record_count')) {
              _recordCount = data['record_count'] as int;
            }
          });
        }
      });

      // 檢查服務是否正在運行
      final isRunning = await FlutterBackgroundService().isRunning();
      if (mounted) {
        setState(() {
          _isAutoRecording = isRunning;
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('初始化失敗: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  // 請求權限
  Future<bool> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先開啟手機的定位服務')),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要定位權限才能使用此功能')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定位權限已被永久拒絕，請至設定中開啟')),
        );
      }
      return false;
    }
    
    return true;
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
      body: !_isInitialized
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('正在初始化...'),
                ],
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: <Widget>[
                // 服務狀態顯示
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isAutoRecording ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _isAutoRecording ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isAutoRecording ? '背景服務運行中' : '背景服務已停止',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isAutoRecording ? Colors.green : Colors.grey,
                              ),
                            ),
                            if (_isAutoRecording && _recordCount > 0)
                              Text(
                                '已記錄 $_recordCount 筆資料',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 背景服務控制開關
                CheckboxListTile(
                  title: const Text('啟動背景自動記錄（每秒）'),
                  subtitle: const Text('App 退到背景也會持續記錄'),
                  value: _isAutoRecording,
                  onChanged: (bool? value) async {
                    if (value == null) return;

                    final service = FlutterBackgroundService();
                    final isRunning = await service.isRunning();

                    if (value) {
                      // 啟動背景服務前先檢查權限
                      final hasPermission = await _checkPermissions();
                      if (!hasPermission) {
                        return;
                      }
                      
                      if (!isRunning) {
                        await service.startService();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('背景服務已啟動，即使退到背景也會繼續記錄'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    } else {
                      if (isRunning) {
                        service.invoke('stopService');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('背景服務已停止')),
                          );
                        }
                      }
                    }

                    setState(() {
                      _isAutoRecording = value;
                    });
                  },
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 20),
                      // 這是新增的 Text 元件，用來顯示時間
                      Text(
                        _timeMessage,
                        style: const TextStyle(
                          fontSize: 18,
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
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          OutlinedButton.icon(
                            onPressed: _memo.isEmpty
                                ? null
                                : _clearMemo, // 如果 MEMO 是空的，則禁用按鈕
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
                                        style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors
                                                .black87), // 4. 調整 MEMO 列表文字樣式
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
