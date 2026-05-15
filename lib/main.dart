import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스캐너',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  String statusText = '인식 대기중';
  String displayInfo = '';
  Color borderColor = Colors.blueAccent;
  Timer? _resetTimer;
  bool _isProcessing = false;
  String? _lastScannedCode;

  // 카메라 제어를 위한 컨트롤러
  final MobileScannerController _cameraController = MobileScannerController();

  // 🌟 슬라이더를 위한 줌 배율 상태 변수 (0.0 ~ 1.0 사이의 값)
  double _currentZoomScale = 0.0;

  final TextEditingController _ipController = TextEditingController(
    text: "203.246.36.222",
  );

  Future<void> processScannedData(
    String scannedValue,
    BarcodeFormat format,
  ) async {
    if (_isProcessing) return;

    final currentIp = _ipController.text.trim();
    if (currentIp.isEmpty) {
      setState(() {
        displayInfo = "IP 주소를 입력해주세요";
        borderColor = Colors.red;
      });
      return;
    }

    _isProcessing = true;

    try {
      if (format == BarcodeFormat.qrCode) {
        final url = Uri.parse('http://$currentIp:8000/api/v1/qr_scan_complete');
        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"customer_name": scannedValue}),
        );

        if (response.statusCode == 200) {
          setState(() {
            displayInfo = "사용자 확인: $scannedValue";
            borderColor = Colors.green;
          });
        } else {
          setState(() {
            displayInfo = "QR 처리 오류";
            borderColor = Colors.orange;
          });
        }
      } else {
        final url = Uri.parse('http://$currentIp:8000/api/v1/scan');
        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"barcode_data": scannedValue}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          setState(() {
            displayInfo = "스캔 완료: ${data['product_name']}";
            borderColor = Colors.green;
          });
        } else {
          setState(() {
            displayInfo = "미등록 상품 ($scannedValue)";
            borderColor = Colors.orange;
          });
        }
      }
    } catch (e) {
      setState(() {
        displayInfo = "서버 연결 실패\nIP 확인: $currentIp";
        borderColor = Colors.red;
      });
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _ipController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스캐너'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 🌟 상단 앱바에 카메라 전환 버튼 배치
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _cameraController.switchCamera(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const SizedBox(height: 20),

              // IP 입력창
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '서버 IP 주소',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.wifi),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 스캐너 영역
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 6),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: borderColor == Colors.green
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.6),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: MobileScanner(
                    controller: _cameraController,
                    onDetect: (BarcodeCapture capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final barcode = barcodes.first;
                        final value = barcode.rawValue ?? '';
                        final format = barcode.format;

                        if (value.isNotEmpty) {
                          if (value == _lastScannedCode) return;
                          _lastScannedCode = value;
                          processScannedData(value, format);

                          setState(() {
                            statusText = format == BarcodeFormat.qrCode
                                ? '✅ QR코드 인식됨'
                                : '✅ 바코드 인식됨';
                          });

                          HapticFeedback.lightImpact();
                          _resetTimer?.cancel();
                          _resetTimer = Timer(
                            const Duration(milliseconds: 2000),
                            () {
                              setState(() {
                                statusText = '인식 대기중';
                                displayInfo = '';
                                borderColor = Colors.blueAccent;
                                _lastScannedCode = null;
                              });
                            },
                          );
                        }
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // 🌟 줌 조절 슬라이더 영역
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.zoom_out),
                        Text(
                          "줌 조절: ${(_currentZoomScale * 100).toInt()}%",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.zoom_in),
                      ],
                    ),
                    Slider(
                      value: _currentZoomScale,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10, // 10단계로 끊어서 조절 가능 (필요시 제거 가능)
                      label: "${(_currentZoomScale * 100).toInt()}%",
                      onChanged: (double value) {
                        setState(() {
                          _currentZoomScale = value;
                          // 🌟 실제 카메라 배율 변경 적용
                          _cameraController.setZoomScale(value);
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                statusText,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: statusText == '인식 대기중' ? Colors.grey : Colors.green,
                ),
              ),

              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  displayInfo,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
