// lib/contact_info_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContactInfoPage extends StatefulWidget {
  static const route = '/contact-info';
  const ContactInfoPage({super.key});

  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage> {
  String? _schoolId;    // e.g., "Somerset K - 5" — passed from previous screen
  String? _schoolLabel; // pretty label
  final TextEditingController _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Expect args from previous page: { 'id': schoolId, 'name': label }
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
    if (args != null && _schoolId == null) {
      _schoolId = args['id'];
      _schoolLabel = args['name'] ?? args['id'];
      setState(() {});
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Contact Info${_schoolLabel != null ? ' • $_schoolLabel' : ''}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: _schoolId == null
            ? const Center(
                child: Text(
                  'No school selected.\nOpen this page from the main screen after choosing a school.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: [
                  // Search only
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: 'Search student',
                          suffixIcon: _search.text.isEmpty
                              ? const Icon(Icons.search)
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Student list
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection(_schoolId!).snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snap.hasError) {
                          return Center(child: Text('Error: ${snap.error}'));
                        }

                        final q = _search.text.trim().toLowerCase();
                        final students = (snap.data?.docs ?? [])
                            .where((doc) {
                              final m = doc.data();
                              if (q.isEmpty) return true;
                              final first = (m['first'] ?? '').toString().toLowerCase();
                              final last  = (m['last'] ?? '').toString().toLowerCase();
                              final full  = '$first $last';
                              return first.contains(q) || last.contains(q) || full.contains(q);
                            })
                            .toList()
                          ..sort((a, b) {
                            final am = a.data(), bm = b.data();
                            final al = (am['last'] ?? '').toString().toLowerCase();
                            final bl = (bm['last'] ?? '').toString().toLowerCase();
                            final cmp = al.compareTo(bl);
                            if (cmp != 0) return cmp;
                            final af = (am['first'] ?? '').toString().toLowerCase();
                            final bf = (bm['first'] ?? '').toString().toLowerCase();
                            return af.compareTo(bf);
                          });

                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: students.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No students found'),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: students.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final doc = students[i];
                                    final m = doc.data();
                                    final first = (m['first'] ?? '').toString();
                                    final last  = (m['last'] ?? '').toString();
                                    final full  = '$first $last'.trim();
                                    final grade = (m['grade'] ?? '').toString();
                                    final teacher = (m['teacher'] ?? '').toString();

                                    return ListTile(
                                      leading: CircleAvatar(child: Text(grade.isEmpty ? '?' : grade)),
                                      title: Text(full, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(teacher.isEmpty ? '' : 'Teacher: $teacher'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => _ContactDetailsPage(
                                              docPath: doc.reference.path,
                                              schoolName: _schoolLabel ?? _schoolId ?? '',
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Details view (same file): shows guardian phone/email with copy buttons.
class _ContactDetailsPage extends StatelessWidget {
  final String docPath;
  final String schoolName;
  const _ContactDetailsPage({required this.docPath, required this.schoolName});

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.doc(docPath);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final d = snap.data!.data() ?? {};
        final full = '${_s(d['first'])} ${_s(d['last'])}'.trim();
        final parent = _s(d['parent']);
        final phone  = _s(d['phone']);
        final email  = _s(d['email']);
        final teacher = _s(d['teacher']);
        final room    = _s(d['roomNumber'] ?? d['room']);
        final grade   = _s(d['grade']);
        final dism    = _s(d['dismissal']);

        Future<void> copy(String label, String value) async {
          if (value.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: value));
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
        }

        Widget row(String label, String value, {VoidCallback? onCopy}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(child: Text(value.isEmpty ? '—' : value)),
                if (onCopy != null)
                  IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy), onPressed: onCopy),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text('Contact • $schoolName')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Text(full, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text([
                      if (grade.isNotEmpty) 'Grade $grade',
                      if (teacher.isNotEmpty) 'Teacher: $teacher',
                      if (room.isNotEmpty) 'Room $room',
                      if (dism.isNotEmpty) dism,
                    ].join(' • ')),
                    const Divider(height: 24),

                    Text('Guardian', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    row('Name', parent),
                    row('Phone', phone, onCopy: () => copy('Phone', phone)),
                    row('Email', email, onCopy: () => copy('Email', email)),

                    const SizedBox(height: 16),
                    const Text(
                      'Tip: Use the copy buttons to paste into your dialer or mail app.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
