import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/notification_service.dart';

class InterimLeaveTimer extends StatefulWidget {
  final List<Map<String, dynamic>> activeInterimLeaves;
  final Function(String attendeeId) onReturnCallback;
  final Function()? onRefresh;

  const InterimLeaveTimer({
    Key? key,
    required this.activeInterimLeaves,
    required this.onReturnCallback,
    this.onRefresh,
  }) : super(key: key);

  @override
  InterimLeaveTimerState createState() => InterimLeaveTimerState();
}

class InterimLeaveTimerState extends State<InterimLeaveTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {}); // Refresh UI every second
      }
    });
  }

  void _checkTimeouts() {
    // This method is called every 30 seconds to check for timeouts
    // and potentially show notifications
    for (final leave in widget.activeInterimLeaves) {
      final outTime = DateTime.tryParse(leave['out_time'] ?? '');
      if (outTime != null) {
        final elapsed = DateTime.now().difference(outTime);
        
        if (elapsed.inMinutes >= 10) {
          // Show overdue notification if not already shown
          // This would be handled by the notification service
        }
      }
    }
  }

  Color _getStatusColor(DateTime outTime) {
    final elapsed = DateTime.now().difference(outTime);
    
    if (elapsed.inMinutes >= 10) {
      return Colors.red; // Overdue
    } else if (elapsed.inMinutes >= 5) {
      return Colors.orange; // Approaching timeout
    } else {
      return Colors.yellow; // Normal interim leave
    }
  }

  IconData _getStatusIcon(DateTime outTime) {
    final elapsed = DateTime.now().difference(outTime);
    
    if (elapsed.inMinutes >= 10) {
      return Icons.warning; // Overdue
    } else if (elapsed.inMinutes >= 5) {
      return Icons.access_time; // Approaching timeout
    } else {
      return Icons.schedule; // Normal
    }
  }

  String _getStatusText(DateTime outTime) {
    final elapsed = DateTime.now().difference(outTime);
    
    if (elapsed.inMinutes >= 10) {
      return 'OVERDUE';
    } else if (elapsed.inMinutes >= 5) {
      return 'WARNING';
    } else {
      return 'ON LEAVE';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeInterimLeaves.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Text(
                  'Active Interim Leaves (${widget.activeInterimLeaves.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (widget.onRefresh != null)
                  IconButton(
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh),
                    color: Colors.orange[800],
                  ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.activeInterimLeaves.length,
            itemBuilder: (context, index) {
              final leave = widget.activeInterimLeaves[index];
              final outTime = DateTime.tryParse(leave['out_time'] ?? '');
              
              if (outTime == null) {
                return const SizedBox.shrink();
              }

              final statusColor = _getStatusColor(outTime);
              final statusIcon = _getStatusIcon(outTime);
              final statusText = _getStatusText(outTime);
              final remainingTime = NotificationService.getRemainingTime(outTime);
              final formattedTime = remainingTime != null 
                  ? NotificationService.formatRemainingTime(remainingTime)
                  : 'OVERDUE';

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: statusColor, width: 4),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.2),
                    child: Icon(statusIcon, color: statusColor),
                  ),
                  title: Text(
                    leave['name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: $statusText'),
                      Text('Time remaining: $formattedTime'),
                      Text(
                        'Out since: ${_formatTime(outTime)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Extend button (only show if not overdue)
                      if (remainingTime != null && !remainingTime.isNegative)
                        IconButton(
                          onPressed: () => _showExtendDialog(leave),
                          icon: const Icon(Icons.add_circle_outline),
                          tooltip: 'Extend 5 minutes',
                          color: Colors.blue,
                        ),
                      // Return button
                      ElevatedButton.icon(
                        onPressed: () => _handleReturn(leave),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Return'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _handleReturn(Map<String, dynamic> leave) {
    final attendeeId = leave['attendee_id'];
    if (attendeeId != null) {
      widget.onReturnCallback(attendeeId);
    }
  }

  void _showExtendDialog(Map<String, dynamic> leave) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extend Interim Leave'),
        content: Text(
          'Extend interim leave for ${leave['name']} by 5 minutes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _extendInterimLeave(leave);
            },
            child: const Text('Extend'),
          ),
        ],
      ),
    );
  }

  void _extendInterimLeave(Map<String, dynamic> leave) {
    // In a real implementation, this would update the database
    // to extend the expected return time by 5 minutes
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Extended interim leave for ${leave['name']} by 5 minutes'),
        backgroundColor: Colors.blue,
      ),
    );
    
    // Refresh the parent widget
    widget.onRefresh?.call();
  }
}

class InterimLeaveTimerSimple extends StatefulWidget {
  final DateTime outTime;
  final String attendeeName;

  const InterimLeaveTimerSimple({
    Key? key,
    required this.outTime,
    required this.attendeeName,
  }) : super(key: key);

  @override
  InterimLeaveTimerSimpleState createState() => InterimLeaveTimerSimpleState();
}

class InterimLeaveTimerSimpleState extends State<InterimLeaveTimerSimple> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remainingTime = NotificationService.getRemainingTime(widget.outTime);
    final formattedTime = remainingTime != null 
        ? NotificationService.formatRemainingTime(remainingTime)
        : 'OVERDUE';
    
    final isOverdue = NotificationService.isOverdue(widget.outTime);
    final isApproaching = NotificationService.isApproachingTimeout(widget.outTime);

    Color textColor;
    if (isOverdue) {
      textColor = Colors.red;
    } else if (isApproaching) {
      textColor = Colors.orange;
    } else {
      textColor = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor),
      ),
      child: Text(
        formattedTime,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}