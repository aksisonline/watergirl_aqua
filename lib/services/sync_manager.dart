import 'dart:async';
import 'package:flutter/material.dart';

/// A base class for syncing data to the server and managing a queue of offline changes.
class SyncManager extends ChangeNotifier {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final List<Function> _queuedSyncs = [];
  Timer? _timer;
  bool _isOnline = true;

  void startSyncTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => syncQueuedChanges());
  }

  void stopSyncTimer() {
    _timer?.cancel();
  }

  void setOnline(bool online) {
    _isOnline = online;
    if (_isOnline) {
      syncQueuedChanges();
    }
  }

  void queueSync(Function syncOperation) {
    _queuedSyncs.add(syncOperation);
    if (_isOnline) {
      syncQueuedChanges();
    }
  }

  Future<void> syncQueuedChanges() async {
    if (!_isOnline) return;
    while (_queuedSyncs.isNotEmpty) {
      final op = _queuedSyncs.removeAt(0);
      try {
        await op();
      } catch (e) {
        // If sync fails, re-queue and break
        _queuedSyncs.insert(0, op);
        break;
      }
    }
    notifyListeners();
  }
}
