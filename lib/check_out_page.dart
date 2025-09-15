import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CheckOutPage extends StatefulWidget {
  static const route = '/check-out';
  const CheckOutPage({super.key});

  @override
  State<CheckOutPage> createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  String? _schoolId;
  String? _schoolLabel;

  // selection
  final Set<String> _selectedIds = {};

  // filter: null = All, else 'pickup' or 'aftercare'
  String? _dismissalFilter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
    if (args != null && _schoolId == null) {
      _schoolId = args['id'];
      _schoolLabel = args['name'] ?? args['id'];
      setState(() {});
    }
  }

  Future<void> _checkoutSelected(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_selectedIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.where((e) => _selectedIds.contains(e.id))) {
      batch.set(d.reference, {
        'status': 'out',
        'checkedIn': false,
        'checkedOutAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checked out ${_selectedIds.length} student(s).')),
      );
      setState(() => _selectedIds.clear());
    }
  }

  void _toggleAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> currentList) {
    setState(() {
      final allSelected = _selectedIds.length == currentList.length && currentList.isNotEmpty;
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(currentList.map((e) => e.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Check-Out${_schoolLabel != null ? ' • $_schoolLabel' : ''}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: _schoolId == null
            ? const Center(
                child: Text(
                  'No school selected.\nOpen from the main screen after choosing a school.',
                  textAlign: TextAlign.center,
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_schoolId!)
                    .where('checkedIn', isEqualTo: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  // All currently "in"
                  final allIn = (snap.data?.docs ?? []).toList()
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

                  // Apply dismissal filter (client-side)
                  final filtered = allIn.where((d) {
                    if (_dismissalFilter == null) return true;
                    final val = (d.data()['dismissal'] ?? '').toString().toLowerCase();
                    return val == _dismissalFilter;
                  }).toList();

                  // If nobody is currently in (even before filtering), show friendly end-state
                  if (allIn.isEmpty) {
                    return Center(
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, size: 64, color: Colors.green),
                              const SizedBox(height: 12),
                              const Text('All set!',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              const Text('Everyone is checked out.', textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                child: const Text('Back'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  // Keep selection valid when data/filters change
                  _selectedIds.removeWhere((id) => !filtered.any((d) => d.id == id));

                  return Column(
                    children: [
                      // Top controls — includes Dismissal filter + responsive counts & actions
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Dismissal filter
                              LayoutBuilder(
                                builder: (context, c) {
                                  final narrow = c.maxWidth < 380;
                                  final drop = SizedBox(
                                    width: narrow ? double.infinity : 220,
                                    child: DropdownButtonFormField<String?>(
                                      value: _dismissalFilter,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Dismissal',
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem<String?>(value: null, child: Text('All')),
                                        DropdownMenuItem<String?>(value: 'pickup', child: Text('Pickup')),
                                        DropdownMenuItem<String?>(value: 'aftercare', child: Text('Aftercare')),
                                      ],
                                      onChanged: (v) => setState(() => _dismissalFilter = v),
                                    ),
                                  );
                                  return drop;
                                },
                              ),
                              const SizedBox(height: 8),
                              // Counts + buttons (responsive)
                              LayoutBuilder(
                                builder: (context, c) {
                                  final narrow = c.maxWidth < 380;
                                  final counts = Text(
                                    'Showing: ${filtered.length} of ${allIn.length} • Selected: ${_selectedIds.length}',
                                    overflow: TextOverflow.ellipsis,
                                  );

                                  final buttons = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: filtered.isEmpty ? null : () => _toggleAll(filtered),
                                        icon: Icon(
                                          _selectedIds.length == filtered.length && filtered.isNotEmpty
                                              ? Icons.check_box
                                              : Icons.check_box_outline_blank,
                                        ),
                                        label: const Text('Select all'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.icon(
                                        onPressed: _selectedIds.isEmpty
                                            ? null
                                            : () => _checkoutSelected(allIn),
                                        // We pass allIn since we filter by ids anyway.
                                        icon: const Icon(Icons.logout),
                                        label: const Text('Check out'),
                                      ),
                                    ],
                                  );

                                  if (!narrow) {
                                    return Row(
                                      children: [
                                        Expanded(child: counts),
                                        const SizedBox(width: 8),
                                        buttons,
                                      ],
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      counts,
                                      const SizedBox(height: 8),
                                      buttons,
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // List of "in" students (filtered) with checkboxes
                      Expanded(
                        child: Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No students match this filter.'),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final doc = filtered[i];
                                    final m = doc.data();
                                    final first = (m['first'] ?? '').toString();
                                    final last = (m['last'] ?? '').toString();
                                    final full = '$first $last'.trim();
                                    final grade = (m['grade'] ?? '').toString();
                                    final teacher = (m['teacher'] ?? '').toString();
                                    final room = (m['roomNumber'] ?? m['room'] ?? '').toString();

                                    final selected = _selectedIds.contains(doc.id);

                                    return ListTile(
                                      onTap: () {
                                        setState(() {
                                          if (selected) {
                                            _selectedIds.remove(doc.id);
                                          } else {
                                            _selectedIds.add(doc.id);
                                          }
                                        });
                                      },
                                      leading: Checkbox(
                                        value: selected,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedIds.add(doc.id);
                                            } else {
                                              _selectedIds.remove(doc.id);
                                            }
                                          });
                                        },
                                      ),
                                      title: Text(full, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text([
                                        if (grade.isNotEmpty) 'Grade $grade',
                                        if (teacher.isNotEmpty) 'Teacher: $teacher',
                                        if (room.isNotEmpty) 'Room $room',
                                      ].join(' • ')),
                                      trailing: IconButton(
                                        tooltip: 'Check out this student',
                                        icon: const Icon(Icons.logout),
                                        onPressed: () async {
                                          setState(() => _selectedIds.add(doc.id));
                                          await _checkoutSelected(allIn);
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
