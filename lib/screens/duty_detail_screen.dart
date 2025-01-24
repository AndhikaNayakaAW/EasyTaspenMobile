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

  // Fallback employees map from `/duty/create`, which can contain both zero-padded and stripped keys
  Map<String, String> _employeesMap = {};

  @override
  void initState() {
    super.initState();
    // 1) Fetch duty detail
    _dutyDetailDataFuture = fetchDutyDetailData(widget.dutyId);
    // 2) Also load global employees map from /duty/create
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
      // fetchEmployeesForCreateDuty merges zero-padded + stripped versions
      final employees = await _apiService.fetchEmployeesForCreateDuty(
        nik: user.nik,
        orgeh: user.orgeh,
        ba: user.ba,
      );
      if (!mounted) return; // Avoid setState if widget is disposed
      setState(() {
        _employeesMap = employees;
      });
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  // ------------------- UI ACTIONS -------------------
  /// Edit duty => open CreateDutyForm
  void _onEdit(Duty duty) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateDutyForm(dutyToEdit: duty),
      ),
    );

    // If user updated or sent the duty, re-fetch the detail
    if (result != null &&
        (result == 'sent' || result == 'updated' || result == 'saved')) {
      if (!mounted) return;
      setState(() {
        _dutyDetailDataFuture = fetchDutyDetailData(widget.dutyId);
      });
    }
  }

  /// Send duty => change from draft/returned to waiting
  void _onSend(Duty duty) async {
    try {
      final user = await _authService.loadUserInfo();
      if (!mounted) return;

      // Minimal request body to transition from "draft"/"returned" to "waiting"
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

  /// Delete duty
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

  Future<Uint8List> _generatePdf(
    PdfPageFormat format,
    DutyDetailData dutyDetailData,
  ) async {
    final pdf = pw.Document();
    final user = dutyDetailData.user;
    final dutyDetail = dutyDetailData.dutyDetail;
    final duty = dutyDetail.duty;
    final approval = dutyDetail.approver;

    final approverName = (approval != null)
        ? _getApproverName(approval.nik, dutyDetail.approverList)
        : "Unknown";

    final creatorName = user.nama ?? "Unknown Creator";
    final creatorNik = user.nik;
    final creatorPosition = user.jabatan ?? "Unknown Position";
    final rejectionReason = approval?.note ?? "";

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Duty Details',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Description: ${duty.description ?? "No Description"}',
                style: const pw.TextStyle(fontSize: 18),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Date: ${_formatDate(duty.dutyDate.toIso8601String())}',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Time: ${_formatTime(duty.startTime)} - ${_formatTime(duty.endTime)}',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.SizedBox(height: 20),

              if (dutyDetail.petugas != null && dutyDetail.petugas!.isNotEmpty)
                ...[
                  pw.Text(
                    'Employee on Duty:',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  for (int i = 0; i < dutyDetail.petugas!.length; i++)
                    pw.Text(
                      '${i + 1}. '
                      '${_getEmployeeName(dutyDetail.petugas![i], dutyDetail.employeeList)} '
                      '(${dutyDetail.petugas![i]})',
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                  pw.SizedBox(height: 16),
                ],

              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.Text(
                'Created:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                  fontSize: 16,
                ),
              ),
              pw.Text(
                _formatDateTime(duty.createdAt),
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Modified:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                  fontSize: 16,
                ),
              ),
              pw.Text(
                _formatDateTime(duty.updatedAt),
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              pw.Text(
                'Created By:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              pw.Text(
                'Name: $creatorName',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'NIK: $creatorNik',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Position: $creatorPosition',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              pw.Text(
                'Approver:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              pw.Text(
                'Name: $approverName',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'NIK: ${approval?.nik ?? "N/A"}',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Position: SENIOR PROGRAMMER',
                style: const pw.TextStyle(fontSize: 16),
              ),

              if (rejectionReason.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Approver Comment:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700,
                    fontSize: 16,
                  ),
                ),
                pw.Text(
                  rejectionReason.isNotEmpty
                      ? rejectionReason
                      : "No comment provided.",
                  style: pw.TextStyle(
                    color: PdfColors.red,
                    fontStyle: pw.FontStyle.italic,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return pdf.save();
  }

  // ------------------- HELPER METHODS -------------------
  /// Looks up by stripped key first, then fallback.  
  String _getEmployeeName(String rawNik, Map<String, String> detailMap) {
    final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');
    final fromDetail = detailMap[strippedNik];
    if (fromDetail != null) return fromDetail;

    // fallback
    final fromGlobal = _employeesMap[strippedNik];
    return fromGlobal ?? "Unknown Employee";
  }

  String _getApproverName(String approverNik, Map<String, String> approverList) {
    return approverList[approverNik] ?? "Unknown";
  }

  /// Submit an approval action (approve/reject/return) with optional komentar
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

                // Submit the chosen status
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

                // Refresh the detail screen
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

  /// Format times like "09:00"
  String _formatTime(String time) {
    try {
      final parsedTime = DateTime.parse("1970-01-01T$time");
      return DateFormat('hh:mm a').format(parsedTime);
    } catch (e) {
      return time;
    }
  }

  /// Format date as dd-MM-yyyy
  String _formatDate(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return DateFormat('dd-MM-yyyy').format(parsedDate);
    } catch (e) {
      return date;
    }
  }

  /// Format dateTime as "MMM dd, yyyy hh:mm a"
  String _formatDateTime(DateTime dateTime) {
    try {
      return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);
    } catch (e) {
      return dateTime.toIso8601String();
    }
  }

  String capitalize(String s) {
    return s.isNotEmpty
        ? s[0].toUpperCase() + s.substring(1).toLowerCase()
        : s;
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

    final approverName = (approval != null)
        ? _getApproverName(approval.nik, dutyDetail.approverList)
        : "Unknown";

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
                // Layout for top section
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
                                // Employees on duty
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
                          // Employees on duty
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

                // Approver Comment (used for any action: reject, approve, or return)
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
                        rejectionReason: approverComment, // Possibly used if needed
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

  // ------------------- BUILD PETUGAS SECTION -------------------
  Widget _buildPetugasSection(GetDutyDetail dutyDetail) {
    if (dutyDetail.petugas == null || dutyDetail.petugas!.isEmpty) {
      return const SizedBox();
    }

    final petugasWidgets = <Widget>[];
    for (int i = 0; i < dutyDetail.petugas!.length; i++) {
      final rawNik = dutyDetail.petugas![i];
      final strippedNik = rawNik.replaceFirst(RegExp(r'^0+'), '');

      // 1) Lookup in the detail's employeeList
      final detailName = dutyDetail.employeeList[strippedNik];
      // 2) If null, fallback to the globally fetched _employeesMap
      final fallbackName = _employeesMap[strippedNik];
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
          // Already showing Approver Comment above
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
