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
  Timer? _focusIndicatorTimer;
  bool _isProcessing = false;
  final RegExp _ean13Pattern = RegExp(r'^\d{13}$');
  static const double _initialZoomScale = 0.5;
  bool _autoZoomEnabled = false;
  Offset? _focusIndicatorPosition;

  // 카메라 제어를 위한 컨트롤러
  late MobileScannerController _cameraController;

  // 🌟 슬라이더를 위한 줌 배율 상태 변수 (0.0 ~ 1.0 사이의 값)
  double _currentZoomScale = _initialZoomScale;

  final TextEditingController _ipController = TextEditingController(
    text: "203.246.36.222",
  );

  MobileScannerController _createCameraController() {
    return MobileScannerController(
      formats: [BarcodeFormat.ean13, BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: 800,
      cameraResolution: const Size(1920, 1080),
      autoZoom: _autoZoomEnabled,
      initialZoom: _initialZoomScale,
    );
  }

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
        if (!_ean13Pattern.hasMatch(scannedValue)) return;

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

  Barcode? _selectBestBarcode(List<Barcode> barcodes) {
    for (final barcode in barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;

      if (barcode.format == BarcodeFormat.ean13 &&
          _ean13Pattern.hasMatch(value)) {
        return barcode;
      }
    }

    for (final barcode in barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;

      if (barcode.format == BarcodeFormat.qrCode) {
        return barcode;
      }
    }

    return null;
  }

  void _toggleAutoZoom() {
    final oldController = _cameraController;

    setState(() {
      _autoZoomEnabled = !_autoZoomEnabled;
      _focusIndicatorPosition = null;
      _cameraController = _createCameraController();
    });

    unawaited(oldController.dispose());
  }

  void _handleFocusTap(TapDownDetails details, Size scannerSize) {
    final localPosition = details.localPosition;
    final focusPoint = Offset(
      (localPosition.dx / scannerSize.width).clamp(0.0, 1.0),
      (localPosition.dy / scannerSize.height).clamp(0.0, 1.0),
    );

    setState(() {
      _focusIndicatorPosition = localPosition;
    });

    HapticFeedback.selectionClick();
    unawaited(_setFocusPoint(focusPoint));

    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      setState(() {
        _focusIndicatorPosition = null;
      });
    });
  }

  Future<void> _setFocusPoint(Offset focusPoint) async {
    try {
      await _cameraController.setFocusPoint(focusPoint);
    } catch (_) {
      // The camera may still be initializing when the user taps.
    }
  }

  @override
  void initState() {
    super.initState();
    _cameraController = _createCameraController();
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _focusIndicatorTimer?.cancel();
    _ipController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scannerSize = MediaQuery.of(context).size.width * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('스캐너'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: _autoZoomEnabled ? '오토줌 끄기' : '오토줌 켜기',
            icon: Icon(
              _autoZoomEnabled
                  ? Icons.center_focus_strong
                  : Icons.center_focus_weak,
            ),
            color: _autoZoomEnabled ? Colors.blue : null,
            onPressed: _toggleAutoZoom,
          ),
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
                width: scannerSize,
                height: scannerSize,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 6),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: borderColor == Colors.green
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(alpha: 0.6),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final focusIndicatorPosition = _focusIndicatorPosition;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _handleFocusTap(details, constraints.biggest),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              key: ValueKey(_autoZoomEnabled),
                              controller: _cameraController,
                              onDetect: (BarcodeCapture capture) {
                                if (_isProcessing) return;

                                final barcode = _selectBestBarcode(
                                  capture.barcodes,
                                );
                                final value = barcode?.rawValue;
                                final format = barcode?.format;

                                if (barcode == null ||
                                    value == null ||
                                    format == null) {
                                  return;
                                }

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
                                    });
                                  },
                                );
                              },
                            ),
                            if (focusIndicatorPosition != null)
                              Positioned(
                                left: focusIndicatorPosition.dx - 22,
                                top: focusIndicatorPosition.dy - 22,
                                child: IgnorePointer(
                                  child: AnimatedScale(
                                    scale: 1,
                                    duration: const Duration(milliseconds: 120),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: const SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Icon(
                                          Icons.center_focus_strong,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
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
