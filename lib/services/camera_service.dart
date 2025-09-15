import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

// Conditional import for Windows camera
import 'package:camera/camera.dart' as camera_package;

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  List<camera_package.CameraDescription> _cameras = [];
  camera_package.CameraController? _currentController;
  int _selectedCameraIndex = 0;
  bool _isWindowsPlatform = false;
  bool _isInitialized = false;

  static const String _cameraPreferenceKey = 'selected_camera_index';

  List<camera_package.CameraDescription> get cameras => _cameras;
  int get selectedCameraIndex => _selectedCameraIndex;
  camera_package.CameraController? get currentController => _currentController;
  camera_package.CameraController? get cameraController => _currentController;
  bool get isWindowsPlatform => _isWindowsPlatform;
  bool get isInitialized => _isInitialized;

  double get previewScale {
    if (_currentController == null || !_currentController!.value.isInitialized) {
      return 1.0;
    }
    return _currentController!.value.aspectRatio;
  }

  Future<void> initialize() async {
    _isWindowsPlatform = !kIsWeb && Platform.isWindows;

    if (!_isWindowsPlatform) return;

    try {
      _cameras = await camera_package.availableCameras();
      await _loadCameraPreference();
      _isInitialized = true;
    } catch (e) {
      print('Error initializing camera service: $e');
    }
  }

  Future<void> _loadCameraPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_cameraPreferenceKey);
      if (savedIndex != null && savedIndex < _cameras.length) {
        _selectedCameraIndex = savedIndex;
      }
    } catch (e) {
      print('Error loading camera preference: $e');
    }
  }

  Future<void> _saveCameraPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cameraPreferenceKey, _selectedCameraIndex);
    } catch (e) {
      print('Error saving camera preference: $e');
    }
  }

  Future<camera_package.CameraController?> initializeCamera([int? cameraIndex]) async {
    if (!_isWindowsPlatform || _cameras.isEmpty) return null;

    final index = cameraIndex ?? _selectedCameraIndex;
    if (index >= _cameras.length) return null;

    // Always dispose any existing controller before starting
    await stopCamera();

    // Try high resolution first, then fallback to medium, then low
    final List<camera_package.ResolutionPreset> presets = [
      camera_package.ResolutionPreset.high,
      camera_package.ResolutionPreset.medium,
      camera_package.ResolutionPreset.low,
    ];

    for (final preset in presets) {
      // Dispose previous controller before creating a new one
      if (_currentController != null) {
        await _currentController!.dispose();
        _currentController = null;
      }
      _currentController = camera_package.CameraController(
        _cameras[index],
        preset,
      );
      try {
        await _currentController!.initialize();
        _selectedCameraIndex = index;
        await _saveCameraPreference();
        print('Camera initialized with preset: '
            '${preset.toString()} on camera index: $index');
        return _currentController;
      } catch (e) {
        print('Error initializing camera controller with preset '
            '${preset.toString()} on camera index $index: $e');
        // Dispose controller on error to ensure native resources are released
        await _currentController?.dispose();
        _currentController = null;
      }
    }
    print('All camera initialization attempts failed for camera index $index.');
    return null;
  }

  Future<void> stopCamera() async {
    if (_currentController != null) {
      await _currentController!.dispose();
      _currentController = null;
    }
  }

  Future<void> setFlashMode(bool enabled) async {
    if (_currentController != null) {
      try {
        await _currentController!.setFlashMode(
          enabled ? camera_package.FlashMode.torch : camera_package.FlashMode.off
        );
      } catch (e) {
        print('Error setting flash mode: $e');
      }
    }
  }

  void dispose() {
    stopCamera();
  }
}
