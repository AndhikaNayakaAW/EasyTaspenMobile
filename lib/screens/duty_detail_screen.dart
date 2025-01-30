// lib/screens/duty_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobileapp/dto/base_response.dart';
import 'package:mobileapp/dto/duty_detail_data.dart';
import 'package:mobileapp/dto/get_duty_detail.dart';
import 'package:mobileapp/enum/user_role.dart';
import 'package:mobileapp/model/approval.dart';
import 'package:mobileapp/model/duty.dart';
import 'package:mobileapp/model/duty_status.dart';
import 'package:mobileapp/model/user.dart';
import 'package:mobileapp/services/api_service_easy_taspen.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/widgets/custom_bottom_app_bar.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
// For loading the Taspen logo asset:
import 'package:flutter/services.dart' show rootBundle;

import 'create_duty_form.dart';
import 'main_screen.dart';
import 'paidleave_cuti_screen.dart';

class DutyDetailScreen extends StatefulWidget {
  final int dutyId;
  final UserRole selectedRole;

  const DutyDetailScreen({
    Key? key,
    required this.dutyId,
    required this.selectedRole,
  }) : super(key: key);

  @override
  State<DutyDetailScreen> createState() => _DutyDetailScreenState();
}

class _DutyDetailScreenState extends State<DutyDetailScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Future for the Duty Detail data
  late Future<DutyDetailData> _dutyDetailDataFuture;

  // Fallback employees map from `/duty/create`,
  // containing both zero-padded and stripped keys
  Map<String, String> _employeesMap = {};

  @override
  void initState() {
    super.initState();
    // 1) Fetch duty detail
    _dutyDetailDataFuture = fetchDutyDetailData(widget.dutyId);
    // 2) Load global employees map
    _loadEmployeeMap();
  }

  // ------------------- FETCH DUTY DETAIL -------------------
  Future<DutyDetailData> fetchDutyDetailData(int dutyId) async {
    try {
      final user = await _authService.loadUserInfo();
      final apiResponse = await _apiService.fetchDutyDetailById(dutyId, user);

      if (apiResponse.metadata.code == 200) {
        final dutyDetail = apiResponse.response!;
        return DutyDetailData(user: user, dutyDetail: dutyDetail);
      } else {
        throw Exception(apiResponse.metadata.message);
      }
    } catch (e) {
      throw Exception('Error fetching data: $e');
    }
  }

  // ------------------- FETCH EMPLOYEE MAP -------------------
  Future<void> _loadEmployeeMap() async {
    try {
      final user = await _authService.loadUserInfo();
      final employees = await _apiService.fetchEmployeesForCreateDuty(
        nik: user.nik,
        orgeh: user.orgeh,
        ba: user.ba,
      );
      if (!mounted) return;
      setState(() {
        _employeesMap = employees;
      });
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  // ------------------- UI ACTIONS -------------------
  void _onEdit(Duty duty) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateDutyForm(dutyToEdit: duty),
      ),
    );

    // If user updated or sent the duty, re-fetch
    if (result != null &&
        (result == 'sent' || result == 'updated' || result == 'saved')) {
      if (!mounted) return;
      setState(() {
        _dutyDetailDataFuture = fetchDutyDetailData(widget.dutyId);
      });
    }
  }

  void _onSend(Duty duty) async {
    try {
      final user = await _authService.loadUserInfo();
      if (!mounted) return;

      final Map<String, dynamic> requestBody = {
        'submit': 'submit',
        'nik': user.nik,
        'username': user.username,
      };

      final response = await _apiService.updateDuty(duty.id, requestBody);

      if (!mounted) return;

      if (response.metadata.code == 200) {
        setState(() {
          _dutyDetailDataFuture = fetchDutyDetailData(widget.dutyId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.response ?? "Duty Sent! Status=Waiting"),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to send duty: ${response.metadata.message}",
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending duty: $e")),
      );
    }
  }

  void _onDelete(Duty duty) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Duty"),
        content: const Text("Are you sure you want to delete this duty?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              try {
                final response = await _apiService.deleteDuty(duty.id);
                if (!mounted) return;
                Navigator.pop(ctx);
                if (response.metadata.code == 200) {
                  Navigator.pop(context, 'deleted');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(response.response.toString())),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Failed to delete duty. Code: ${response.metadata.code}",
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error deleting duty: $e")),
                );
              }
            },
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------- PRINTING -------------------
  void _onPrint(DutyDetailData dutyDetailData) async {
    try {
      await Printing.layoutPdf(
        onLayout: (format) => _generatePdf(format, dutyDetailData),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to generate PDF: $e")),
      );
    }
  }

  /// EXACT PDF MODEL from your snippet,
  /// but with the same name-lookup logic used in duty details
  Future<Uint8List> _generatePdf(
    PdfPageFormat format,
    DutyDetailData dutyDetailData,
  ) async {
    final pdf = pw.Document();

    // Load Taspen Logo
    final logoData = await rootBundle.load('assets/images/taspenlogo.jpg');
    final Uint8List logoBytes = logoData.buffer.asUint8List();

    // Extract details
    final user = dutyDetailData.user;            // The Maker (logged in)
    final detail = dutyDetailData.dutyDetail;
    final duty = detail.duty;
    final approval = detail.approver;

    // -------------- NAME LOOKUP (same as _buildPetugasSection) --------------
    String _employeeNameForPdf(String rawNik) {
      final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');

      // 1) Check dutyDetail's local map (employeeList)
      final fromDetail = detail.employeeList[strippedNik] ??
          detail.employeeList[rawNik];
      if (fromDetail != null) return fromDetail;

      // 2) If null, fallback to the globally fetched map
      final fromGlobal = _employeesMap[strippedNik] ?? _employeesMap[rawNik];
      return fromGlobal ?? "Unknown";
    }

    // Approver name uses dutyDetail.approverList => fallback to _employeesMap
    String _approverNameForPdf(String rawNik) {
      final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');

      // 1) Check dutyDetail.approverList
      final fromDetail = detail.approverList[strippedNik] ??
          detail.approverList[rawNik];
      if (fromDetail != null) return fromDetail;

      // 2) Fallback to global
      final fromGlobal = _employeesMap[strippedNik] ?? _employeesMap[rawNik];
      return fromGlobal ?? "Unknown Approver";
    }

    // We want the final "approver name" in the signature
    final approverName = (approval != null)
        ? _approverNameForPdf(approval.nik)
        : "Unknown Approver";

    // Format date/time
    String _formatDate(String dateStr) {
      try {
        final parsedDate = DateTime.parse(dateStr);
        return DateFormat('dd-MM-yyyy').format(parsedDate);
      } catch (e) {
        return dateStr;
      }
    }

    String _formatTime(String timeStr) {
      try {
        final parsedTime = DateTime.parse("1970-01-01T$timeStr");
        return DateFormat('HH:mm:ss').format(parsedTime);
      } catch (e) {
        return timeStr;
      }
    }

    // Create the PDF
    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Logo & Title
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Image(pw.MemoryImage(logoBytes), width: 100),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          "PT TASPEN (PERSERO)",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          "SURAT PERINTAH TUGAS",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          "No: ___________",
                          style: pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    pw.SizedBox(width: 100), // alignment
                  ],
                ),
                pw.SizedBox(height: 20),

                // **Section 1: Employee Table**
                pw.Text(
                  "I. Diperintahkan Kepada:",
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 8),
                pw.Table.fromTextArray(
                  headers: ["NO", "NIK", "NAMA"],
                  data: detail.petugas!.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final nik = entry.value; // raw NIK from petugas
                    final name = _employeeNameForPdf(nik);
                    return [index.toString(), nik, name];
                  }).toList(),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                  cellStyle: pw.TextStyle(fontSize: 10),
                  border: pw.TableBorder.all(),
                  cellAlignment: pw.Alignment.centerLeft,
                ),
                pw.SizedBox(height: 20),

                // **Section 2: Task Description**
                pw.Text(
                  "II. Untuk Melaksanakan Tugas Sebagai Berikut:",
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 8),
                pw.Bullet(
                  text: duty.description ?? "Tidak ada deskripsi tugas",
                  style: pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 20),

                // **Section 3: Date & Time**
                pw.Text(
                  "III. Yang dilaksanakan pada:",
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "1. Tanggal: ${_formatDate(duty.dutyDate.toIso8601String())}",
                      style: pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      "2. Berangkat Jam: ${_formatTime(duty.startTime)}",
                      style: pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      "3. Kembali Jam: ${_formatTime(duty.endTime)}",
                      style: pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),

                // **Section 4: Closing Statement**
                pw.Text(
                  "IV. Tugas tersebut supaya dilaksanakan dengan penuh rasa tanggung jawab "
                  "dan melaporkan hasilnya kepada pejabat yang memerintahkan.",
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),

                // Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Approver Signature
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          "Yang Menyetujui Tugas/Dinas",
                          style: pw.TextStyle(fontSize: 12),
                        ),
                        pw.SizedBox(height: 40),
                        pw.Text(
                          approverName,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        // Example static position
                        pw.Text(
                          "(SENIOR PROGRAMMER)",
                          style: pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    // Maker's (creator) Signature
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          "Yang Melaksanakan,",
                          style: pw.TextStyle(fontSize: 12),
                        ),
                        pw.Text(
                          "Tugas/Dinas",
                          style: pw.TextStyle(fontSize: 12),
                        ),
                        pw.SizedBox(height: 40),

                        // Maker name
                        pw.Text(
                          user.nama ?? "Unknown",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        // ADDED: Maker's position under signature
                        pw.Text(
                          "(${user.jabatan ?? "Unknown Position"})",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),

                // Footer
                pw.SizedBox(height: 20),
                pw.Text(
                  "Dengan Motor / Mobil No.: Mobil/Motor",
                  style: pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ------------------- HELPER METHODS -------------------
  /// Same logic for the detail UI employees
  String _getEmployeeName(String rawNik, Map<String, String> detailMap) {
    final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');
    // Check the detailMap
    final fromDetail = detailMap[strippedNik] ?? detailMap[rawNik];
    if (fromDetail != null) return fromDetail;

    // fallback to _employeesMap
    final fromGlobal = _employeesMap[strippedNik] ?? _employeesMap[rawNik];
    return fromGlobal ?? "Unknown Employee";
  }

  /// Same logic for the detail UI approver
  String _getApproverName(String rawNik, Map<String, String> approverList) {
    final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');
    final fromDetail = approverList[strippedNik] ?? approverList[rawNik];
    if (fromDetail != null) return fromDetail;

    final fromGlobal = _employeesMap[strippedNik] ?? _employeesMap[rawNik];
    return fromGlobal ?? "Unknown";
  }

  /// Submit an approval action
  Future<void> _onSubmitApproval(Duty duty, DutyStatus newStatus) async {
    final komentarController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          (newStatus == DutyStatus.approved)
              ? "Approve Duty"
              : (newStatus == DutyStatus.rejected)
                  ? "Reject Duty"
                  : "Return Duty",
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (newStatus == DutyStatus.approved)
                  ? "Are you sure you want to approve this duty?"
                  : (newStatus == DutyStatus.rejected)
                      ? "Are you sure you want to reject this duty?"
                      : "Are you sure you want to return this duty?",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: komentarController,
              decoration: const InputDecoration(
                labelText: "Komentar (Optional)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final user = await _authService.loadUserInfo();
                if (!mounted) return;

                await _apiService.submitApproval(
                  duty.id,
                  newStatus,
                  user,
                  komentarController.text,
                );

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      (newStatus == DutyStatus.approved)
                          ? "Duty approved!"
                          : (newStatus == DutyStatus.rejected)
                              ? "Duty rejected!"
                              : "Duty returned!",
                    ),
                    backgroundColor: Colors.green,
                  ),
                );

                if (!mounted) return;
                setState(() {
                  _dutyDetailDataFuture = fetchDutyDetailData(duty.id);
                });
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              (newStatus == DutyStatus.approved)
                  ? "Approve"
                  : (newStatus == DutyStatus.rejected)
                      ? "Reject"
                      : "Return",
            ),
          ),
        ],
      ),
    );
  }

  // Time formatting
  String _formatTime(String time) {
    try {
      final parsedTime = DateTime.parse("1970-01-01T$time");
      return DateFormat('hh:mm a').format(parsedTime);
    } catch (e) {
      return time;
    }
  }

  // Date formatting
  String _formatDate(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return DateFormat('dd-MM-yyyy').format(parsedDate);
    } catch (e) {
      return date;
    }
  }

  // DateTime formatting
  String _formatDateTime(DateTime dateTime) {
    try {
      return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);
    } catch (e) {
      return dateTime.toIso8601String();
    }
  }

  String capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  // ------------------- UI BUILD -------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Duty Detail"),
        backgroundColor: Colors.teal,
      ),
      body: FutureBuilder<DutyDetailData>(
        future: _dutyDetailDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else if (snapshot.hasData) {
            final dutyDetailData = snapshot.data!;
            final user = dutyDetailData.user;
            final dutyDetail = dutyDetailData.dutyDetail;
            final duty = dutyDetail.duty;

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) {
                  // Large screen
                  return Row(
                    children: [
                      // Sidebar
                      Container(
                        width: 250,
                        color: Colors.teal.shade50,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.edit),
                              label: const Text("Edit Duty Form"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () => _onEdit(duty),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.home),
                              label: const Text("Home"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MainScreen(),
                                  ),
                                  (Route<dynamic> route) => false,
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.airline_seat_flat),
                              label: const Text("Paid Leave (Cuti)"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PaidLeaveCutiScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Main Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: _buildDetailContent(
                            user: user,
                            dutyDetail: dutyDetail,
                            isMobile: false,
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // Mobile
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildDetailContent(
                      user: user,
                      dutyDetail: dutyDetail,
                      isMobile: true,
                    ),
                  );
                }
              },
            );
          } else {
            return const Center(child: Text("No data available."));
          }
        },
      ),
      bottomNavigationBar: const CustomBottomAppBar(),
    );
  }

  /// Builds the detail content for both mobile & large screens
  Widget _buildDetailContent({
    required User user,
    required GetDutyDetail dutyDetail,
    bool isMobile = false,
  }) {
    final duty = dutyDetail.duty;
    if (duty == null) {
      return const Center(
        child: Text(
          "Duty information is not available.",
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    final approval = dutyDetail.approver;
    final description = duty.description ?? "No Description";
    final displayedDate = _formatDate(duty.dutyDate.toIso8601String());
    final displayedStart = _formatTime(duty.startTime);
    final displayedEnd = _formatTime(duty.endTime);

    // Creator info
    final creatorName = user.nama ?? "Unknown Creator";
    final creatorNik = user.nik;
    final creatorPosition = user.jabatan ?? "Unknown Position";

    // Approver
    final approverName = (approval != null)
        ? _getApproverName(approval.nik, dutyDetail.approverList)
        : "Unknown Approver";

    // The "komentar" from approver
    final approverComment = approval?.note ?? "";

    // Evaluate statuses
    final isDraft = (duty.status == DutyStatus.draft);
    final isWaiting = (duty.status == DutyStatus.waiting);
    final isApproved = (duty.status == DutyStatus.approved);
    final isReturned = (duty.status == DutyStatus.returned);
    final isRejected = (duty.status == DutyStatus.rejected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Duty Details",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top section
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 500) {
                      // Large layout
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  description,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Date: $displayedDate",
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Text(
                                  "Time: $displayedStart - $displayedEnd",
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 10),
                                _buildPetugasSection(dutyDetail),
                              ],
                            ),
                          ),
                          const SizedBox(width: 40),
                          // Right side
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Created:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDateTime(duty.createdAt),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Modified:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDateTime(duty.updatedAt),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      );
                    } else {
                      // Mobile layout
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Date: $displayedDate",
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Time: $displayedStart - $displayedEnd",
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 10),
                          _buildPetugasSection(dutyDetail),
                          const SizedBox(height: 20),
                          Text(
                            "Created:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(duty.createdAt),
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Modified:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(duty.updatedAt),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),

                // Created By
                const Row(
                  children: [
                    Icon(Icons.person, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      "Created By:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Name: $creatorName",
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  "NIK: $creatorNik",
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  "Position: $creatorPosition",
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),

                // Approver
                const Row(
                  children: [
                    Icon(Icons.approval, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      "Approver:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Name: $approverName",
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  "NIK: ${approval != null ? approval.nik : "N/A"}",
                  style: const TextStyle(fontSize: 16),
                ),
                const Text(
                  "Position: SENIOR PROGRAMMER",
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 16),
                const Divider(),
                Text(
                  "Approver Comment:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  approverComment.isNotEmpty
                      ? approverComment
                      : "No comment provided.",
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),

                // Role-based buttons
                (widget.selectedRole == UserRole.maker)
                    ? _buildActionButtonsMaker(
                        duty,
                        isDraft: isDraft,
                        isReturned: isReturned,
                        isWaiting: isWaiting,
                        isApproved: isApproved,
                        isRejected: isRejected,
                        rejectionReason: approverComment,
                        dutyDetailData: DutyDetailData(
                          user: user,
                          dutyDetail: dutyDetail,
                        ),
                      )
                    : _buildActionButtonsApprover(duty),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------------------- BUILD PETUGAS SECTION (UI) -------------------
  Widget _buildPetugasSection(GetDutyDetail dutyDetail) {
    if (dutyDetail.petugas == null || dutyDetail.petugas!.isEmpty) {
      return const SizedBox();
    }

    final petugasWidgets = <Widget>[];
    for (int i = 0; i < dutyDetail.petugas!.length; i++) {
      final rawNik = dutyDetail.petugas![i];
      final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');

      // Same logic used above
      final detailName =
          dutyDetail.employeeList[strippedNik] ?? dutyDetail.employeeList[rawNik];
      final fallbackName =
          _employeesMap[strippedNik] ?? _employeesMap[rawNik];
      final name = detailName ?? fallbackName ?? "Unknown Employee";

      petugasWidgets.add(
        Text(
          "${i + 1}. $name ($rawNik)",
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Employee on Duty:",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        ...petugasWidgets,
      ],
    );
  }

  // ------------------- APPROVER ACTIONS -------------------
  Widget _buildActionButtonsApprover(Duty duty) {
    final status = duty.status;
    final isReturn = (status == DutyStatus.returned);
    final isNeedApprove = (status == DutyStatus.waiting);

    final buttons = <Widget>[];

    // Approver can take actions if waiting or returned
    if (isNeedApprove || isReturn) {
      buttons.addAll([
        ElevatedButton.icon(
          icon: const Icon(Icons.check_circle),
          label: const Text("Approve"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            textStyle: const TextStyle(fontSize: 16),
          ),
          onPressed: () => _onSubmitApproval(duty, DutyStatus.approved),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.keyboard_return_sharp),
          label: const Text("Return"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            textStyle: const TextStyle(fontSize: 16),
          ),
          onPressed: () => _onSubmitApproval(duty, DutyStatus.returned),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.cancel),
          label: const Text("Reject"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            textStyle: const TextStyle(fontSize: 16),
          ),
          onPressed: () => _onSubmitApproval(duty, DutyStatus.rejected),
        ),
      ]);
    }

    // Print is always available
    buttons.addAll([
      const SizedBox(width: 10),
      ElevatedButton.icon(
        icon: const Icon(Icons.print),
        label: const Text("Print"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          textStyle: const TextStyle(fontSize: 16),
        ),
        onPressed: () async {
          final dutyDetailData = await _dutyDetailDataFuture;
          _onPrint(dutyDetailData);
        },
      ),
    ]);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: buttons),
    );
  }

  // ------------------- MAKER ACTIONS -------------------
  Widget _buildActionButtonsMaker(
    Duty duty, {
    required bool isDraft,
    required bool isReturned,
    required bool isWaiting,
    required bool isApproved,
    required bool isRejected,
    required String rejectionReason,
    required DutyDetailData dutyDetailData,
  }) {
    final status = duty.status.makerDesc;

    if (isDraft) {
      return Row(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text("Edit"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onEdit(duty),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text("Send"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onSend(duty),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text("Delete"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onDelete(duty),
          ),
        ],
      );
    } else if (isReturned) {
      return Row(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text("Edit"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onEdit(duty),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text("Send"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onSend(duty),
          ),
        ],
      );
    } else if (isWaiting || isApproved) {
      // Only Print
      return ElevatedButton.icon(
        icon: const Icon(Icons.print),
        label: Text("Print (${capitalize(status)})"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          textStyle: const TextStyle(fontSize: 16),
        ),
        onPressed: () => _onPrint(dutyDetailData),
      );
    } else if (isRejected) {
      // Rejected => Possibly just print
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: Text("Print (${capitalize(status)})"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => _onPrint(dutyDetailData),
          ),
          const SizedBox(height: 10),
          // Approver Comment is already shown above
        ],
      );
    } else {
      // Fallback
      return ElevatedButton.icon(
        icon: const Icon(Icons.print),
        label: Text("Print (${capitalize(status)})"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          textStyle: const TextStyle(fontSize: 16),
        ),
        onPressed: () => _onPrint(dutyDetailData),
      );
    }
  }
}
