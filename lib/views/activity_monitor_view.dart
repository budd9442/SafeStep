import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class ActivityMonitorView extends StatefulWidget {
  const ActivityMonitorView({Key? key}) : super(key: key);
  @override
  State<ActivityMonitorView> createState() => _ActivityMonitorViewState();
}

class _ActivityMonitorViewState extends State<ActivityMonitorView> {
  final List<List<dynamic>> _data = [];
  StreamSubscription<AccelerometerEvent>? _accelSub;
  static const int maxRows = 200;
  Interpreter? interpreter;
  Map<String, dynamic>? labelMap;
  String activity = '';
  double activityProb = 0.0;
  bool modelLoaded = false;
  final int _windowSize = 100; // 2s at 50Hz
  final int _windowStep = 50; // 50% overlap
  List<List<double>> _window = [];
  double accMin = -4.0;
  double accMax = 4.0;
  String distress = '';
  double distressProb = 0.0;

  @override
  void initState() {
    super.initState();
    _loadModelAndLabels();
    _accelSub = accelerometerEvents.listen((event) {
      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      final row = [now, event.x, event.y, event.z];
      setState(() {
        _data.add(row);
        if (_data.length > maxRows) _data.removeAt(0);
      });
      // Add to window for prediction
      final norm = [
        (event.x - accMin) / (accMax - accMin),
        (event.y - accMin) / (accMax - accMin),
        (event.z - accMin) / (accMax - accMin),
      ];
      _window.add(norm);
      if (_window.length >= _windowSize && modelLoaded) {
        _runInference(List<List<double>>.from(_window));
        _window = _window.sublist(_windowStep);
      }
    });
  }

  Future<void> _loadModelAndLabels() async {
    print('[TFLITE] Attempting to download model and load labels...');
    try {
      // Download model from web
      final url = 'https://github.com/budd9442/SafeStep/raw/refs/heads/master/assets/model.tflite';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('[TFLITE][ERROR] Failed to download model: HTTP \\${response.statusCode}');
        setState(() { modelLoaded = false; });
        return;
      }
      final dir = await getTemporaryDirectory();
      // Use a unique filename each time to avoid caching
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch.toString();
      final modelPath = '${dir.path}/model_$uniqueSuffix.tflite';
      final modelFile = File(modelPath);
      await modelFile.writeAsBytes(response.bodyBytes);
      print('[TFLITE] Model downloaded to $modelPath');
      interpreter = await Interpreter.fromFile(modelFile);
      print('[TFLITE] Model loaded from file.');
      // Print output tensor details using correct API
      final outputTensors = interpreter!.getOutputTensors();
      final outputCount = outputTensors.length;
      for (var i = 0; i < outputCount; i++) {
        print('[TFLITE][DEBUG] Output $i: name=${outputTensors[i].name}, shape=${outputTensors[i].shape}, type=${outputTensors[i].type}');
      }
      // Load labels from assets
      String labelJson = await rootBundle.loadString('assets/activity_labels.json');
      print('[TFLITE] Label JSON loaded: $labelJson');
      labelMap = json.decode(labelJson);
      print('[TFLITE] Label map parsed: $labelMap');
      setState(() {
        modelLoaded = true;
      });
    } catch (e) {
      print('[TFLITE][ERROR] Failed to download/load model or labels: $e');
      setState(() {
        modelLoaded = false;
      });
    }
  }

  void _runInference(List<List<double>> window) {
    if (interpreter == null) {
      print('[TFLITE][ERROR] Interpreter is null');
      return;
    }
    final inputTensor = [window];

    // Dynamically handle outputs based on model
    final outputCount = interpreter!.getOutputTensors().length;
    print('[TFLITE][DEBUG] Model output count: $outputCount');
    try {
      if (outputCount == 2) {
        // Multi-output: activity and distress
        final activityShape = interpreter!.getOutputTensor(0).shape;
        final distressShape = interpreter!.getOutputTensor(1).shape;
        print('[TFLITE][DEBUG] Activity output shape: $activityShape, Distress output shape: $distressShape');
        final activityOutput = List.filled(activityShape.reduce((a, b) => a * b), 0.0).reshape(activityShape);
        final distressOutput = List.filled(distressShape.reduce((a, b) => a * b), 0.0).reshape(distressShape);
        interpreter!.runForMultipleInputs([inputTensor], {0: activityOutput, 1: distressOutput});
        print('[TFLITE][OUTPUT] activity: $activityOutput, distress: $distressOutput');
        // Get activity prediction
        int activityIdx = 0;
        double maxProb = activityOutput[0][0];
        for (int i = 1; i < activityOutput[0].length; i++) {
          if (activityOutput[0][i] > maxProb) {
            maxProb = activityOutput[0][i];
            activityIdx = i;
          }
        }
        String activityLabel = labelMap![activityIdx.toString()] ?? 'Unknown';
        // Get distress prediction
        double newDistressProb = distressOutput[0][0];
        String newDistress = newDistressProb > 0.8 ? 'Yes' : 'No';
        setState(() {
          activity = activityLabel;
          activityProb = maxProb;
          distress = newDistress;
          distressProb = newDistressProb;
        });
      } else if (outputCount == 1) {
        // Single output: print shape and handle as distress or activity
        final outShape = interpreter!.getOutputTensor(0).shape;
        print('[TFLITE][DEBUG] Single output shape: $outShape');
        final output = List.filled(outShape.reduce((a, b) => a * b), 0.0).reshape(outShape);
        interpreter!.run(inputTensor, output);
        print('[TFLITE][OUTPUT] output: $output');
        if (outShape[1] == 1) {
          // Likely distress only
          double newDistressProb = output[0][0];
          String newDistress = newDistressProb > 0.8 ? 'Yes' : 'No';
          setState(() {
            activity = 'Unknown';
            activityProb = 0.0;
            distress = newDistress;
            distressProb = newDistressProb;
          });
        } else {
          // Likely activity only
          int activityIdx = 0;
          double maxProb = output[0][0];
          for (int i = 1; i < output[0].length; i++) {
            if (output[0][i] > maxProb) {
              maxProb = output[0][i];
              activityIdx = i;
            }
          }
          String activityLabel = labelMap![activityIdx.toString()] ?? 'Unknown';
          setState(() {
            activity = activityLabel;
            activityProb = maxProb;
            distress = 'Unknown';
            distressProb = 0.0;
          });
        }
      } else {
        print('[TFLITE][ERROR] Unexpected number of outputs: $outputCount');
        setState(() {
          activity = 'Error';
          activityProb = 0.0;
          distress = 'Error';
          distressProb = 0.0;
        });
      }
    } catch (e) {
      print('[TFLITE][ERROR] Inference failed: $e');
      setState(() {
        activity = 'Error';
        activityProb = 0.0;
        distress = 'Error';
        distressProb = 0.0;
      });
      return;
    }
  }
  @override
  void dispose() {
    _accelSub?.cancel();
    interpreter?.close();
    super.dispose();
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('timestamp')),
          DataColumn(label: Text('acc_x')),
          DataColumn(label: Text('acc_y')),
          DataColumn(label: Text('acc_z')),
        ],
        rows: _data.reversed.take(50).map((row) => DataRow(cells: [
          DataCell(Text(row[0].toStringAsExponential(6))),
          DataCell(Text(row[1].toStringAsFixed(6))),
          DataCell(Text(row[2].toStringAsFixed(6))),
          DataCell(Text(row[3].toStringAsFixed(6))),
        ])).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity & Distress Monitor')),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prediction: $activity (prob=${activityProb.toStringAsFixed(2)})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Distress: $distress (prob=${distressProb.toStringAsFixed(2)})', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            const Text('Live Accelerometer Data (last 50 rows):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(child: _buildTable()),
          ],
        ),
      ),
    );
  }
}
