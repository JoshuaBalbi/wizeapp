import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditStudentPage extends StatefulWidget {
  static const route = '/edit-student';
  const EditStudentPage({super.key});

  @override
  State<EditStudentPage> createState() => _EditStudentPageState();
}

class _EditStudentPageState extends State<EditStudentPage> {
  final _formKey = GlobalKey<FormState>();

  late final DocumentReference<Map<String, dynamic>> _ref;
  late final String _title;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _grade = TextEditingController();
  final _teacher = TextEditingController();
  final _room = TextEditingController();   // optional
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String _dismissal = 'pickup';

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final path = (args['docPath'] ?? '').toString();
    _title = (args['schoolName'] ?? '').toString();
    _ref = FirebaseFirestore.instance.doc(path).withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => snap.data() ?? {},
      toFirestore: (data, _) => data,
    );
  }

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

  int _toInt(String v) => int.tryParse(v.trim()) ?? 0;
  int? _toIntOrNull(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final roomVal = _toIntOrNull(_room.text);

    final updates = <String, dynamic>{
      'first': _first.text.trim(),
      'last': _last.text.trim(),
      'grade': _toInt(_grade.text),
      'teacher': _teacher.text.trim(),
      'dismissal': _dismissal,
      'parent': _guardian.text.trim(),
      'phone': _toInt(_phone.text),
      'email': _email.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // handle optional room
    if (roomVal == null) {
      updates['roomNumber'] = FieldValue.delete();
      updates['room'] = FieldValue.delete();
    } else {
      updates['roomNumber'] = roomVal;
      updates['room'] = roomVal;
    }

    await _ref.set(updates, SetOptions(merge: true));

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data() ?? {};
        // Fill once
        if (!_loaded) {
          _first.text = (data['first'] ?? '').toString();
          _last.text = (data['last'] ?? '').toString();
          _grade.text = (data['grade'] ?? '').toString();
          _teacher.text = (data['teacher'] ?? '').toString();
          _room.text = (data['roomNumber'] ?? data['room'] ?? '').toString();
          _guardian.text = (data['parent'] ?? '').toString();
          _phone.text = (data['phone'] ?? '').toString();
          _email.text = (data['email'] ?? '').toString();
          final dism = (data['dismissal'] ?? 'pickup').toString();
          _dismissal = (dism == 'aftercare') ? 'aftercare' : 'pickup';
          _loaded = true;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Edit Student • $_title'),
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                  decoration: const InputDecoration(labelText: 'Guardian phone (numbers only)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Guardian email'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save changes'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
