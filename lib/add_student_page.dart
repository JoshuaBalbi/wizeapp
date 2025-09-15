import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Use 'teacher' sections by default. Change to 'roomNumber' if you prefer.
const String kSectionField = 'teacher';

class AddStudentPage extends StatefulWidget {
  static const route = '/add-student';
  const AddStudentPage({super.key});

  @override
  State<AddStudentPage> createState() => _AddStudentPageState();
}

class _AddStudentPageState extends State<AddStudentPage> {
  final _formKey = GlobalKey<FormState>();

  // Passed in via route settings:
  late final String _schoolId;      // e.g., "Somerset K - 5"
  late final String _schoolLabel;   // same as id if not provided
  String? _prefilledSection;        // teacher or roomNumber value

  // Controllers
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _grade = TextEditingController();
  final _teacher = TextEditingController();
  final _room = TextEditingController();        // ← optional
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  String _dismissal = 'pickup'; // default

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _grade.dispose();
    _teacher.dispose();
    _room.dispose();
    _guardian.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Accept args from CheckInPage (supports either {'id','name','section'} or {'schoolId','schoolName'})
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    _schoolId = (args['id'] ?? args['schoolId'])?.toString() ?? '';
    _schoolLabel = (args['name'] ?? args['schoolName'] ?? _schoolId).toString();
    _prefilledSection = args['section']?.toString();

    // Prefill relevant field from the section
    if (_prefilledSection != null && _prefilledSection!.isNotEmpty) {
      if (kSectionField == 'teacher') {
        _teacher.text = _prefilledSection!;
      } else if (kSectionField == 'roomNumber') {
        _room.text = _prefilledSection!;
      }
    }
  }

  int _toInt(String v) => int.tryParse(v.trim()) ?? 0;
  int? _toIntOrNull(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _save() async {
    if (_schoolId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a school first.')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final roomVal = _toIntOrNull(_room.text); // ← may be null if left empty

    final data = <String, dynamic>{
      'first': _first.text.trim(),
      'last': _last.text.trim(),
      'grade': _toInt(_grade.text),
      'teacher': _teacher.text.trim(),
      // only include room fields when provided
      if (roomVal != null) 'room': roomVal,
      if (roomVal != null) 'roomNumber': roomVal, // optional, keeps UI compatibility
      'dismissal': _dismissal, // 'pickup' | 'aftercare'
      'parent': _guardian.text.trim(),
      'phone': _toInt(_phone.text),
      'email': _email.text.trim(),
      'status': 'pending',
      'checkedIn': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance.collection(_schoolId).add(data);

    if (mounted) {
      Navigator.of(context).pop(true); // return to list and refresh
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student added')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionLabel = kSectionField == 'teacher' ? 'Teacher' : 'Room Number';
    final sectionController = kSectionField == 'teacher' ? _teacher : _room;
    final sectionKeyboard = kSectionField == 'teacher'
        ? TextInputType.text
        : TextInputType.number;

    return Scaffold(
      appBar: AppBar(
        title: Text('Add Student • $_schoolLabel'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(labelText: 'First name'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _last,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _grade,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _room,
                    decoration: const InputDecoration(labelText: 'Room number (optional)'),
                    keyboardType: TextInputType.number,
                    // no validator → optional
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Section field (teacher or room), prefilled from current section when available
            TextFormField(
              controller: sectionController,
              decoration: InputDecoration(labelText: sectionLabel),
              keyboardType: sectionKeyboard,
              validator: (v) => (kSectionField == 'teacher' && (v == null || v.trim().isEmpty))
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _dismissal,
              decoration: const InputDecoration(labelText: 'Dismissal'),
              items: const [
                DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                DropdownMenuItem(value: 'aftercare', child: Text('Aftercare')),
              ],
              onChanged: (v) => setState(() => _dismissal = v ?? 'pickup'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _guardian,
              decoration: const InputDecoration(labelText: 'Guardian name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Guardian phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Guardian email'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save student'),
            ),
          ],
        ),
      ),
    );
  }
}
