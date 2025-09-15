import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'add_student_page.dart';
import 'edit_student_page.dart';

enum SortKey { alpha, teacher, room, dismissal, grade }

// Keep 'teacher' unless you want sections by room
const String kSectionField = 'teacher';

class CheckInPage extends StatefulWidget {
  static const route = '/check-in';
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  // selected school = the top-level collection name that holds student docs
  String? _schoolId;     // e.g., "Somerset K - 5"
  String? _schoolLabel;  // pretty label (same as id for now)

  // sorting
  SortKey _sort = SortKey.alpha;
  bool _ascending = true;

  // filters
  String? _filterTeacher;     // null = All
  String? _filterDismissal;   // null = All, else 'pickup' | 'aftercare'
  String? _filterGradeStr;    // null = All, else '3', '4', ...
  String? _filterRoomStr;     // null = All, else '101', '202', ...
  bool _filtersOpen = true;

  // edit mode (tap a student to edit)
  bool _selectToEdit = false;

  // ----- helpers -----
  String _statusOf(Map<String, dynamic> d) =>
      (d['status'] as String?)?.toLowerCase() ?? 'pending';

  Color _tileColor(BuildContext ctx, String status) {
    switch (status) {
      case 'in':
        return Colors.green.withOpacity(0.15);
      case 'absent':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.transparent;
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  int _cmp(String a, String b) => a.compareTo(b);

  int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    int r;
    switch (_sort) {
      case SortKey.alpha:
        final al = (a['last'] ?? '').toString().toLowerCase();
        final bl = (b['last'] ?? '').toString().toLowerCase();
        r = _cmp(al, bl);
        if (r == 0) {
          final af = (a['first'] ?? '').toString().toLowerCase();
          final bf = (b['first'] ?? '').toString().toLowerCase();
          r = _cmp(af, bf);
        }
        break;
      case SortKey.teacher:
        r = _cmp((a['teacher'] ?? '').toString(), (b['teacher'] ?? '').toString());
        break;
      case SortKey.room:
        r = _asInt(a['roomNumber']).compareTo(_asInt(b['roomNumber']));
        break;
      case SortKey.dismissal:
        r = _cmp((a['dismissal'] ?? '').toString(), (b['dismissal'] ?? '').toString());
        break;
      case SortKey.grade:
        r = _asInt(a['grade']).compareTo(_asInt(b['grade']));
        break;
    }
    return _ascending ? r : -r;
  }

  Future<void> _setStatus(
    DocumentReference<Map<String, dynamic>> ref,
    String status,
  ) async {
    await ref.set({
      'status': status,
      'checkedIn': status == 'in',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _openAddStudent() async {
    if (_schoolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a school first')),
      );
      return;
    }
    final sectionArg =
        (kSectionField == 'teacher') ? _filterTeacher : _filterRoomStr;

    final args = {
      'id': _schoolId!,
      'name': _schoolLabel ?? _schoolId!,
      'section': sectionArg,
    };
    await Navigator.of(context).pushNamed(AddStudentPage.route, arguments: args);
  }

  Future<void> _openEditStudent(DocumentReference ref) async {
    await Navigator.of(context).pushNamed(
      EditStudentPage.route,
      arguments: {
        'docPath': ref.path,
        'schoolName': _schoolLabel ?? _schoolId ?? '',
      },
    );
    if (mounted) setState(() => _selectToEdit = false);
  }

  void _clearFilters() {
    _filterTeacher = null;
    _filterDismissal = null;
    _filterGradeStr = null;
    _filterRoomStr = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
    if (args != null && _schoolId == null) {
      setState(() {
        _schoolId = args['id'];
        _schoolLabel = args['name'] ?? args['id'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Check-In${_schoolLabel != null ? ' • $_schoolLabel' : ''}'),
        actions: [
          IconButton(
            tooltip: _ascending ? 'Ascending' : 'Descending',
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () => setState(() => _ascending = !_ascending),
          ),
          PopupMenuButton<SortKey>(
            initialValue: _sort,
            icon: const Icon(Icons.sort),
            onSelected: (k) => setState(() => _sort = k),
            itemBuilder: (context) => const [
              PopupMenuItem(value: SortKey.alpha, child: Text('Alphabetical')),
              PopupMenuItem(value: SortKey.teacher, child: Text('Teacher')),
              PopupMenuItem(value: SortKey.room, child: Text('Room number')),
              PopupMenuItem(value: SortKey.dismissal, child: Text('Dismissal type')),
              PopupMenuItem(value: SortKey.grade, child: Text('Grade')),
            ],
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: _schoolId == null
                  ? const Center(child: Text('Select a school to view students'))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection(_schoolId!).snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));

                        final allDocs = (snap.data?.docs ?? []).toList();

                        // Distinct options for filter dropdowns
                        final teacherSet = <String>{};
                        final gradeSet = <int>{};
                        final roomSet  = <int>{};
                        for (final d in allDocs) {
                          final m = d.data();
                          final t = (m['teacher'] ?? '').toString();
                          if (t.isNotEmpty) teacherSet.add(t);
                          final g = _asIntOrNull(m['grade']);
                          if (g != null) gradeSet.add(g);
                          final r = _asIntOrNull(m['roomNumber']);
                          if (r != null) roomSet.add(r);
                        }
                        final teacherList = teacherSet.toList()..sort();
                        final gradeList = gradeSet.toList()..sort();
                        final roomList = roomSet.toList()..sort();

                        // Validate current filter selections
                        if (_filterTeacher != null && !teacherList.contains(_filterTeacher)) {
                          _filterTeacher = null;
                        }
                        if (_filterGradeStr != null &&
                            int.tryParse(_filterGradeStr!) != null &&
                            !gradeList.contains(int.parse(_filterGradeStr!))) {
                          _filterGradeStr = null;
                        }
                        if (_filterRoomStr != null &&
                            int.tryParse(_filterRoomStr!) != null &&
                            !roomList.contains(int.parse(_filterRoomStr!))) {
                          _filterRoomStr = null;
                        }
                        if (_filterDismissal != null &&
                            !['pickup', 'aftercare'].contains(_filterDismissal)) {
                          _filterDismissal = null;
                        }

                        // Apply filters client-side
                        final filtered = allDocs.where((doc) {
                          final m = doc.data();
                          if (_filterTeacher != null &&
                              (m['teacher'] ?? '').toString() != _filterTeacher) {
                            return false;
                          }
                          if (_filterDismissal != null &&
                              (m['dismissal'] ?? '').toString() != _filterDismissal) {
                            return false;
                          }
                          if (_filterGradeStr != null) {
                            final want = int.tryParse(_filterGradeStr!);
                            if (want != null && _asInt(m['grade']) != want) return false;
                          }
                          if (_filterRoomStr != null) {
                            final want = int.tryParse(_filterRoomStr!);
                            if (want != null && _asInt(m['roomNumber']) != want) return false;
                          }
                          return true;
                        }).toList();

                        // Sort the filtered list
                        filtered.sort((a, b) => _compare(a.data(), b.data()));

                        // counts from filtered subset
                        int inCount = 0, absentCount = 0, pendingCount = 0;
                        for (final d in filtered) {
                          switch (_statusOf(d.data())) {
                            case 'in': inCount++; break;
                            case 'absent': absentCount++; break;
                            default: pendingCount++; break;
                          }
                        }

                        return Column(
                          children: [
                            // Collapsible Filters + counters
                            Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('Filters',
                                            style: TextStyle(fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        TextButton.icon(
                                          onPressed: () => setState(_clearFilters),
                                          icon: const Icon(Icons.filter_alt_off, size: 18),
                                          label: const Text('Clear', style: TextStyle(fontSize: 12)),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            minimumSize: const Size(0, 32),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: _filtersOpen ? 'Collapse' : 'Expand',
                                          icon: Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more),
                                          onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                                        ),
                                      ],
                                    ),
                                    AnimatedCrossFade(
                                      duration: const Duration(milliseconds: 180),
                                      crossFadeState: _filtersOpen
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                      firstChild: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: DropdownButtonFormField<String?>(
                                                  value: _filterTeacher,
                                                  isExpanded: true,
                                                  decoration: const InputDecoration(labelText: 'Teacher'),
                                                  items: [
                                                    const DropdownMenuItem<String?>(value: null, child: Text('All')),
                                                    ...teacherList.map((t) =>
                                                        DropdownMenuItem<String?>(value: t, child: Text(t))),
                                                  ],
                                                  onChanged: (v) => setState(() => _filterTeacher = v),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: DropdownButtonFormField<String?>(
                                                  value: _filterDismissal,
                                                  isExpanded: true,
                                                  decoration: const InputDecoration(labelText: 'Dismissal'),
                                                  items: const [
                                                    DropdownMenuItem<String?>(value: null, child: Text('All')),
                                                    DropdownMenuItem<String?>(value: 'pickup', child: Text('Pickup')),
                                                    DropdownMenuItem<String?>(value: 'aftercare', child: Text('Aftercare')),
                                                  ],
                                                  onChanged: (v) => setState(() => _filterDismissal = v),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: DropdownButtonFormField<String?>(
                                                  value: _filterGradeStr,
                                                  isExpanded: true,
                                                  decoration: const InputDecoration(labelText: 'Grade'),
                                                  items: [
                                                    const DropdownMenuItem<String?>(value: null, child: Text('All')),
                                                    ...gradeList.map((g) =>
                                                        DropdownMenuItem<String?>(
                                                          value: g.toString(),
                                                          child: Text(g.toString()),
                                                        )),
                                                  ],
                                                  onChanged: (v) => setState(() => _filterGradeStr = v),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: DropdownButtonFormField<String?>(
                                                  value: _filterRoomStr,
                                                  isExpanded: true,
                                                  decoration: const InputDecoration(labelText: 'Room #'),
                                                  items: [
                                                    const DropdownMenuItem<String?>(value: null, child: Text('All')),
                                                    ...roomList.map((r) =>
                                                        DropdownMenuItem<String?>(
                                                          value: r.toString(),
                                                          child: Text(r.toString()),
                                                        )),
                                                  ],
                                                  onChanged: (v) => setState(() => _filterRoomStr = v),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      ),
                                      secondChild: const SizedBox.shrink(),
                                    ),
                                    Row(
                                      children: [
                                        _CountChipSmall(label: 'In', count: inCount, color: Colors.green),
                                        const SizedBox(width: 8),
                                        _CountChipSmall(label: 'Abs', count: absentCount, color: Colors.red),
                                        const SizedBox(width: 8),
                                        _CountChipSmall(label: 'Not yet', count: pendingCount, color: Colors.grey),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),

                            if (_selectToEdit)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit, size: 18),
                                    const SizedBox(width: 8),
                                    const Expanded(child: Text('Tap a student to edit')),
                                    TextButton(
                                      onPressed: () => setState(() => _selectToEdit = false),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ),

                            // Student list + footer "Add / Edit" section
                            Expanded(
                              child: ListView.separated(
                                itemCount: (filtered.isEmpty ? 1 : filtered.length + 1),
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final isFooter = i == filtered.length || filtered.isEmpty;
                                  if (isFooter) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                                      child: Card(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Actions',
                                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: FilledButton.icon(
                                                      onPressed: _openAddStudent,
                                                      icon: const Icon(Icons.person_add),
                                                      label: const Text('Add new'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: OutlinedButton.icon(
                                                      onPressed: () => setState(() => _selectToEdit = true),
                                                      icon: const Icon(Icons.edit),
                                                      label: const Text('Edit existing'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final doc = filtered[i];
                                  final ref = doc.reference;
                                  final d = doc.data();

                                  final first = (d['first'] ?? '').toString();
                                  final last  = (d['last'] ?? '').toString();
                                  final full  = '$first $last'.trim();
                                  final grade = (d['grade'] ?? '').toString();
                                  final teacher = (d['teacher'] ?? '').toString();
                                  final room = (d['roomNumber'] ?? '').toString();
                                  final dism = (d['dismissal'] ?? '').toString();
                                  final status = _statusOf(d);

                                  return Container(
                                    color: _tileColor(context, status),
                                    child: ListTile(
                                      onTap: _selectToEdit ? () => _openEditStudent(ref) : null,
                                      leading: CircleAvatar(child: Text(grade.isEmpty ? '?' : grade)),
                                      title: Text(full, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text([
                                        if (teacher.isNotEmpty) 'Teacher: $teacher',
                                        if (room.isNotEmpty) 'Room $room',
                                        if (dism.isNotEmpty) dism,
                                      ].join(' • ')),
                                      trailing: _selectToEdit
                                          ? const Icon(Icons.chevron_right)
                                          : Wrap(
                                              spacing: 6,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Checked in',
                                                  onPressed: () => _setStatus(ref, 'in'),
                                                  icon: const Icon(Icons.check_circle),
                                                  color: Colors.green,
                                                ),
                                                IconButton(
                                                  tooltip: 'Absent',
                                                  onPressed: () => _setStatus(ref, 'absent'),
                                                  icon: const Icon(Icons.cancel),
                                                  color: Colors.red,
                                                ),
                                                IconButton(
                                                  tooltip: 'Not yet',
                                                  onPressed: () => _setStatus(ref, 'pending'),
                                                  icon: const Icon(Icons.radio_button_unchecked),
                                                ),
                                              ],
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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

class _CountChipSmall extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChipSmall({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text('$label: $count', style: const TextStyle(fontSize: 12)),
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}


// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'add_student_page.dart';

// enum SortKey { alpha, teacher, room, dismissal, grade }

// // Keep 'teacher' unless you want sections by room
// const String kSectionField = 'teacher';

// class CheckInPage extends StatefulWidget {
//   static const route = '/check-in';
//   const CheckInPage({super.key});

//   @override
//   State<CheckInPage> createState() => _CheckInPageState();
// }

// class _CheckInPageState extends State<CheckInPage> {
//   // selected school = the top-level collection name that holds student docs
//   String? _schoolId;     // e.g., "Somerset K - 5"
//   String? _schoolLabel;  // pretty label (same as id for now)

//   // sorting
//   SortKey _sort = SortKey.alpha;
//   bool _ascending = true;

//   // filters
//   String? _filterTeacher;     // null = All
//   String? _filterDismissal;   // null = All, else 'pickup' | 'aftercare'
//   String? _filterGradeStr;    // null = All, else '3', '4', ...
//   String? _filterRoomStr;     // null = All, else '101', '202', ...
//   bool _filtersOpen = true;

//   // ----- helpers -----
//   String _statusOf(Map<String, dynamic> d) =>
//       (d['status'] as String?)?.toLowerCase() ?? 'pending';

//   Color _tileColor(BuildContext ctx, String status) {
//     switch (status) {
//       case 'in':
//         return Colors.green.withOpacity(0.15);
//       case 'absent':
//         return Colors.red.withOpacity(0.15);
//       default:
//         return Colors.transparent;
//     }
//   }

//   int _asInt(dynamic v) {
//     if (v is int) return v;
//     return int.tryParse(v?.toString() ?? '') ?? 0;
//   }

//   int? _asIntOrNull(dynamic v) {
//     if (v == null) return null;
//     if (v is int) return v;
//     return int.tryParse(v.toString());
//   }

//   int _cmp(String a, String b) => a.compareTo(b);

//   int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
//     int r;
//     switch (_sort) {
//       case SortKey.alpha:
//         final al = (a['last'] ?? '').toString().toLowerCase();
//         final bl = (b['last'] ?? '').toString().toLowerCase();
//         r = _cmp(al, bl);
//         if (r == 0) {
//           final af = (a['first'] ?? '').toString().toLowerCase();
//           final bf = (b['first'] ?? '').toString().toLowerCase();
//           r = _cmp(af, bf);
//         }
//         break;
//       case SortKey.teacher:
//         r = _cmp((a['teacher'] ?? '').toString(), (b['teacher'] ?? '').toString());
//         break;
//       case SortKey.room:
//         r = _asInt(a['roomNumber']).compareTo(_asInt(b['roomNumber']));
//         break;
//       case SortKey.dismissal:
//         r = _cmp((a['dismissal'] ?? '').toString(), (b['dismissal'] ?? '').toString());
//         break;
//       case SortKey.grade:
//         r = _asInt(a['grade']).compareTo(_asInt(b['grade']));
//         break;
//     }
//     return _ascending ? r : -r;
//   }

//   Future<void> _setStatus(
//     DocumentReference<Map<String, dynamic>> ref,
//     String status,
//   ) async {
//     await ref.set({
//       'status': status,
//       'checkedIn': status == 'in',
//       'updatedAt': FieldValue.serverTimestamp(),
//     }, SetOptions(merge: true));
//   }

//   void _openAddStudent() async {
//     if (_schoolId == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Select a school first')),
//       );
//       return;
//     }
//     // Prefill teacher (or room) based on current filters
//     final sectionArg =
//         (kSectionField == 'teacher') ? _filterTeacher : _filterRoomStr;

//     final args = {
//       'id': _schoolId!,
//       'name': _schoolLabel ?? _schoolId!,
//       'section': sectionArg, // AddStudentPage will prefill if kSectionField matches
//     };
//     await Navigator.of(context).pushNamed(AddStudentPage.route, arguments: args);
//   }

//   void _clearFilters() {
//     _filterTeacher = null;
//     _filterDismissal = null;
//     _filterGradeStr = null;
//     _filterRoomStr = null;
//   }

//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     // Pick up optional args from Home: {'id': schoolId, 'name': label}
//     final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
//     if (args != null && _schoolId == null) {
//       setState(() {
//         _schoolId = args['id'];
//         _schoolLabel = args['name'] ?? args['id'];
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title:
//             Text('Check-In${_schoolLabel != null ? ' • $_schoolLabel' : ''}'),
//         actions: [
//           IconButton(
//             tooltip: _ascending ? 'Ascending' : 'Descending',
//             icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
//             onPressed: () => setState(() => _ascending = !_ascending),
//           ),
//           PopupMenuButton<SortKey>(
//             initialValue: _sort,
//             icon: const Icon(Icons.sort),
//             onSelected: (k) => setState(() => _sort = k),
//             itemBuilder: (context) => const [
//               PopupMenuItem(value: SortKey.alpha, child: Text('Alphabetical')),
//               PopupMenuItem(value: SortKey.teacher, child: Text('Teacher')),
//               PopupMenuItem(value: SortKey.room, child: Text('Room number')),
//               PopupMenuItem(value: SortKey.dismissal, child: Text('Dismissal type')),
//               PopupMenuItem(value: SortKey.grade, child: Text('Grade')),
//             ],
//           ),
//         ],
//       ),

//       body: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(
//           children: [
//             // FILTERS + STUDENT LIST (single stream)
//             Expanded(
//               child: _schoolId == null
//                   ? const Center(child: Text('Select a school to view students'))
//                   : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                       stream: FirebaseFirestore.instance.collection(_schoolId!).snapshots(),
//                       builder: (context, snap) {
//                         if (snap.connectionState == ConnectionState.waiting) {
//                           return const Center(child: CircularProgressIndicator());
//                         }
//                         if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));

//                         final allDocs = (snap.data?.docs ?? []).toList();

//                         // Distinct options for filter dropdowns
//                         final teacherSet = <String>{};
//                         final gradeSet = <int>{};
//                         final roomSet  = <int>{};
//                         for (final d in allDocs) {
//                           final m = d.data();
//                           final t = (m['teacher'] ?? '').toString();
//                           if (t.isNotEmpty) teacherSet.add(t);
//                           final g = _asIntOrNull(m['grade']);
//                           if (g != null) gradeSet.add(g);
//                           final r = _asIntOrNull(m['roomNumber']);
//                           if (r != null) roomSet.add(r);
//                         }
//                         final teacherList = teacherSet.toList()..sort();
//                         final gradeList = gradeSet.toList()..sort();
//                         final roomList = roomSet.toList()..sort();

//                         // Validate current filter selections
//                         if (_filterTeacher != null && !teacherList.contains(_filterTeacher)) {
//                           _filterTeacher = null;
//                         }
//                         if (_filterGradeStr != null &&
//                             int.tryParse(_filterGradeStr!) != null &&
//                             !gradeList.contains(int.parse(_filterGradeStr!))) {
//                           _filterGradeStr = null;
//                         }
//                         if (_filterRoomStr != null &&
//                             int.tryParse(_filterRoomStr!) != null &&
//                             !roomList.contains(int.parse(_filterRoomStr!))) {
//                           _filterRoomStr = null;
//                         }
//                         if (_filterDismissal != null &&
//                             !['pickup', 'aftercare'].contains(_filterDismissal)) {
//                           _filterDismissal = null;
//                         }

//                         // Apply filters client-side
//                         final filtered = allDocs.where((doc) {
//                           final m = doc.data();
//                           if (_filterTeacher != null &&
//                               (m['teacher'] ?? '').toString() != _filterTeacher) {
//                             return false;
//                           }
//                           if (_filterDismissal != null &&
//                               (m['dismissal'] ?? '').toString() != _filterDismissal) {
//                             return false;
//                           }
//                           if (_filterGradeStr != null) {
//                             final want = int.tryParse(_filterGradeStr!);
//                             if (want != null && _asInt(m['grade']) != want) return false;
//                           }
//                           if (_filterRoomStr != null) {
//                             final want = int.tryParse(_filterRoomStr!);
//                             if (want != null && _asInt(m['roomNumber']) != want) return false;
//                           }
//                           return true;
//                         }).toList();

//                         // Sort the filtered list
//                         filtered.sort((a, b) => _compare(a.data(), b.data()));

//                         // counts from filtered subset
//                         int inCount = 0, absentCount = 0, pendingCount = 0;
//                         for (final d in filtered) {
//                           switch (_statusOf(d.data())) {
//                             case 'in': inCount++; break;
//                             case 'absent': absentCount++; break;
//                             default: pendingCount++; break;
//                           }
//                         }

//                         // ---- UI ----
//                         return Column(
//                           children: [
//                             // Collapsible Filters card + small one-line counters
//                             Card(
//                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
//                               child: Padding(
//                                 padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.stretch,
//                                   children: [
//                                     // Header row
//                                     Row(
//                                       children: [
//                                         const Text('Filters',
//                                             style: TextStyle(fontWeight: FontWeight.w600)),
//                                         const Spacer(),
//                                         TextButton.icon(
//                                           onPressed: () => setState(_clearFilters),
//                                           icon: const Icon(Icons.filter_alt_off, size: 18),
//                                           label: const Text('Clear', style: TextStyle(fontSize: 12)),
//                                           style: TextButton.styleFrom(
//                                             padding: const EdgeInsets.symmetric(
//                                                 horizontal: 8, vertical: 6),
//                                             minimumSize: const Size(0, 32),
//                                           ),
//                                         ),
//                                         IconButton(
//                                           tooltip: _filtersOpen ? 'Collapse' : 'Expand',
//                                           icon: Icon(
//                                               _filtersOpen ? Icons.expand_less : Icons.expand_more),
//                                           onPressed: () =>
//                                               setState(() => _filtersOpen = !_filtersOpen),
//                                         ),
//                                       ],
//                                     ),

//                                     // Collapsible body
//                                     AnimatedCrossFade(
//                                       duration: const Duration(milliseconds: 180),
//                                       crossFadeState: _filtersOpen
//                                           ? CrossFadeState.showFirst
//                                           : CrossFadeState.showSecond,
//                                       firstChild: Column(
//                                         children: [
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: DropdownButtonFormField<String?>(
//                                                   value: _filterTeacher,
//                                                   isExpanded: true,
//                                                   decoration: const InputDecoration(labelText: 'Teacher'),
//                                                   items: [
//                                                     const DropdownMenuItem<String?>(
//                                                       value: null, child: Text('All')),
//                                                     ...teacherList.map((t) =>
//                                                         DropdownMenuItem<String?>(
//                                                             value: t, child: Text(t))),
//                                                   ],
//                                                   onChanged: (v) =>
//                                                       setState(() => _filterTeacher = v),
//                                                 ),
//                                               ),
//                                               const SizedBox(width: 12),
//                                               Expanded(
//                                                 child: DropdownButtonFormField<String?>(
//                                                   value: _filterDismissal,
//                                                   isExpanded: true,
//                                                   decoration: const InputDecoration(labelText: 'Dismissal'),
//                                                   items: const [
//                                                     DropdownMenuItem<String?>(
//                                                         value: null, child: Text('All')),
//                                                     DropdownMenuItem<String?>(
//                                                         value: 'pickup', child: Text('Pickup')),
//                                                     DropdownMenuItem<String?>(
//                                                         value: 'aftercare', child: Text('Aftercare')),
//                                                   ],
//                                                   onChanged: (v) =>
//                                                       setState(() => _filterDismissal = v),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                           const SizedBox(height: 12),
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: DropdownButtonFormField<String?>(
//                                                   value: _filterGradeStr,
//                                                   isExpanded: true,
//                                                   decoration: const InputDecoration(labelText: 'Grade'),
//                                                   items: [
//                                                     const DropdownMenuItem<String?>(
//                                                         value: null, child: Text('All')),
//                                                     ...gradeList.map((g) =>
//                                                         DropdownMenuItem<String?>(
//                                                           value: g.toString(),
//                                                           child: Text(g.toString()),
//                                                         )),
//                                                   ],
//                                                   onChanged: (v) =>
//                                                       setState(() => _filterGradeStr = v),
//                                                 ),
//                                               ),
//                                               const SizedBox(width: 12),
//                                               Expanded(
//                                                 child: DropdownButtonFormField<String?>(
//                                                   value: _filterRoomStr,
//                                                   isExpanded: true,
//                                                   decoration: const InputDecoration(labelText: 'Room #'),
//                                                   items: [
//                                                     const DropdownMenuItem<String?>(
//                                                         value: null, child: Text('All')),
//                                                     ...roomList.map((r) =>
//                                                         DropdownMenuItem<String?>(
//                                                           value: r.toString(),
//                                                           child: Text(r.toString()),
//                                                         )),
//                                                   ],
//                                                   onChanged: (v) =>
//                                                       setState(() => _filterRoomStr = v),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                           const SizedBox(height: 8),
//                                         ],
//                                       ),
//                                       secondChild: const SizedBox.shrink(),
//                                     ),

//                                     // Small one-line counters
//                                     Row(
//                                       children: [
//                                         _CountChipSmall(label: 'In', count: inCount, color: Colors.green),
//                                         const SizedBox(width: 8),
//                                         _CountChipSmall(label: 'Abs', count: absentCount, color: Colors.red),
//                                         const SizedBox(width: 8),
//                                         _CountChipSmall(label: 'Not yet', count: pendingCount, color: Colors.grey),
//                                       ],
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ),
//                             const Divider(height: 1),

//                             // Student list + footer "Add Student" section as the LAST item
//                             Expanded(
//                               child: ListView.separated(
//                                 itemCount: (filtered.isEmpty ? 1 : filtered.length + 1),
//                                 separatorBuilder: (_, __) => const Divider(height: 1),
//                                 itemBuilder: (_, i) {
//                                   final isFooter = i == filtered.length || filtered.isEmpty;
//                                   if (isFooter) {
//                                     return Padding(
//                                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
//                                       child: Card(
//                                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
//                                         child: Padding(
//                                           padding: const EdgeInsets.all(16),
//                                           child: Column(
//                                             crossAxisAlignment: CrossAxisAlignment.start,
//                                             children: [
//                                               const Text('Add Student',
//                                                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
//                                               const SizedBox(height: 12),
//                                               Align(
//                                                 alignment: Alignment.center,
//                                                 child: FilledButton.icon(
//                                                   onPressed: _openAddStudent,
//                                                   icon: const Icon(Icons.person_add),
//                                                   label: const Text('Add new'),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                         ),
//                                       ),
//                                     );
//                                   }

//                                   final doc = filtered[i];
//                                   final ref = doc.reference;
//                                   final d = doc.data();

//                                   final first = (d['first'] ?? '').toString();
//                                   final last  = (d['last'] ?? '').toString();
//                                   final full  = '$first $last'.trim();
//                                   final grade = (d['grade'] ?? '').toString();
//                                   final teacher = (d['teacher'] ?? '').toString();
//                                   final room = (d['roomNumber'] ?? '').toString();
//                                   final dism = (d['dismissal'] ?? '').toString();
//                                   final status = _statusOf(d);

//                                   return Container(
//                                     color: _tileColor(context, status),
//                                     child: ListTile(
//                                       leading: CircleAvatar(child: Text(grade.isEmpty ? '?' : grade)),
//                                       title: Text(full, style: const TextStyle(fontWeight: FontWeight.w600)),
//                                       subtitle: Text([
//                                         if (teacher.isNotEmpty) 'Teacher: $teacher',
//                                         if (room.isNotEmpty) 'Room $room',
//                                         if (dism.isNotEmpty) dism,
//                                       ].join(' • ')),
//                                       trailing: Wrap(
//                                         spacing: 6,
//                                         children: [
//                                           IconButton(
//                                             tooltip: 'Checked in',
//                                             onPressed: () => _setStatus(ref, 'in'),
//                                             icon: const Icon(Icons.check_circle),
//                                             color: Colors.green,
//                                           ),
//                                           IconButton(
//                                             tooltip: 'Absent',
//                                             onPressed: () => _setStatus(ref, 'absent'),
//                                             icon: const Icon(Icons.cancel),
//                                             color: Colors.red,
//                                           ),
//                                           IconButton(
//                                             tooltip: 'Not yet',
//                                             onPressed: () => _setStatus(ref, 'pending'),
//                                             icon: const Icon(Icons.radio_button_unchecked),
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   );
//                                 },
//                               ),
//                             ),
//                           ],
//                         );
//                       },
//                     ),
//             ),
//           ],
//         ),
//       ),
//       // No FloatingActionButton — footer card handles "Add Student"
//     );
//   }
// }

// class _CountChipSmall extends StatelessWidget {
//   final String label;
//   final int count;
//   final Color color;
//   const _CountChipSmall({required this.label, required this.count, required this.color});

//   @override
//   Widget build(BuildContext context) {
//     return Chip(
//       avatar: CircleAvatar(backgroundColor: color, radius: 6),
//       labelPadding: const EdgeInsets.symmetric(horizontal: 6),
//       label: Text('$label: $count', style: const TextStyle(fontSize: 12)),
//       side: BorderSide.none,
//       materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//     );
//   }
// }

