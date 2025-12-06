import 'package:flutter/material.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'vlvt_button.dart';
import 'vlvt_input.dart';

/// Bottom sheet for creating a date proposal
class DateProposalSheet extends StatefulWidget {
  final String matchName;
  final Function({
    required String placeName,
    required DateTime proposedDate,
    required String proposedTime,
    String? placeAddress,
    String? note,
  }) onSubmit;

  const DateProposalSheet({
    super.key,
    required this.matchName,
    required this.onSubmit,
  });

  @override
  State<DateProposalSheet> createState() => _DateProposalSheetState();
}

class _DateProposalSheetState extends State<DateProposalSheet> {
  final _placeController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  bool _isSubmitting = false;

  @override
  void dispose() {
    _placeController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: VlvtColors.gold,
              onPrimary: Colors.black,
              surface: VlvtColors.surface,
              onSurface: VlvtColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: VlvtColors.gold,
              onPrimary: Colors.black,
              surface: VlvtColors.surface,
              onSurface: VlvtColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _submit() {
    if (_placeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a venue name'),
          backgroundColor: VlvtColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final timeString = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    widget.onSubmit(
      placeName: _placeController.text.trim(),
      proposedDate: _selectedDate,
      proposedTime: timeString,
      placeAddress: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
    );
  }

  String get _formattedDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[_selectedDate.weekday - 1]}, ${months[_selectedDate.month - 1]} ${_selectedDate.day}';
  }

  String get _formattedTime {
    int hour = _selectedTime.hour;
    final minute = _selectedTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: VlvtColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VlvtColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Row(
              children: [
                Icon(Icons.calendar_today, color: VlvtColors.gold, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Propose a Date',
                  style: VlvtTextStyles.h2.copyWith(color: VlvtColors.gold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ask ${widget.matchName} out!',
              style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Venue name
            VlvtInput(
              controller: _placeController,
              hintText: 'Venue name',
              prefixIcon: Icons.place,
            ),
            const SizedBox(height: 12),

            // Address (optional)
            VlvtInput(
              controller: _addressController,
              hintText: 'Address (optional)',
              prefixIcon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),

            // Date and Time pickers
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: VlvtColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VlvtColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, color: VlvtColors.gold, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formattedDate,
                            style: VlvtTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _selectTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: VlvtColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VlvtColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: VlvtColors.gold, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formattedTime,
                            style: VlvtTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Note (optional)
            VlvtInput(
              controller: _noteController,
              hintText: 'Add a note (optional)',
              prefixIcon: Icons.note_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Submit button
            VlvtButton.primary(
              label: _isSubmitting ? 'Sending...' : 'Send Proposal',
              onPressed: _isSubmitting ? null : _submit,
              icon: Icons.send,
              expanded: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
