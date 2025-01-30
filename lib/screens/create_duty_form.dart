// lib/screens/create_duty_form.dart

import 'package:flutter/material.dart';
import 'package:mobileapp/dto/base_response.dart';
import 'package:mobileapp/dto/create_duty_response.dart';
import 'package:mobileapp/dto/get_duty_detail.dart';
import 'package:mobileapp/model/approval.dart';
import 'package:mobileapp/model/duty.dart';
import 'package:mobileapp/model/duty_status.dart';
import 'package:mobileapp/model/employee_duty.dart';
import 'package:mobileapp/model/user.dart';
import 'package:mobileapp/services/api_service_easy_taspen.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/widgets/custom_bottom_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Import dropdown_search for searchable dropdowns
import 'package:dropdown_search/dropdown_search.dart';

class CreateDutyForm extends StatefulWidget {
  /// If non-null, we're editing an existing duty.
  final Duty? dutyToEdit;

  /// Optional: If we need the existing approval info while editing.
  final Approval? approvalToEdit;

  const CreateDutyForm({
    Key? key,
    this.dutyToEdit,
    this.approvalToEdit,
  }) : super(key: key);

  @override
  CreateDutyFormState createState() => CreateDutyFormState();
}

class CreateDutyFormState extends State<CreateDutyForm> {
  // ----- Services -----
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // ----- Fetched Data Variables -----
  /// Master list of employees: e.g. { "00004163": "John Doe", "00004199": "Jane Smith" }
  Map<String, String> _employeeList = {};

  /// Approver list: e.g. { "60001": "CEO", "60002": "CFO" }
  Map<String, String> _approverList = {};

  /// Transport list: e.g. { "1": "Disediakan Perusahaan", "2": "Kendaraan Pribadi" }
  Map<String, String> _transportList = {};

  // ----- State Variables -----
  bool isLoading = false;
  String? errorMessage;

  // Description
  String _description = "";

  // List of selected employees for this duty
  List<EmployeeDuty> _employeeDuties = [
    EmployeeDuty(employeeId: "", employeeName: ""),
  ];

  // Single approver
  String? _selectedApproverId;

  // Duty date/time
  DateTime? _selectedDutyDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Transport
  String? _selectedTransport;

  // Rejection Reason (only if duty is in "rejected" status)
  String? _rejectionReason;
  bool isRejected = false;

  // Dropdown action selection
  String? _selectedAction;

  // Original (initial) data for reset
  String _initialDescription = "";
  List<EmployeeDuty> _initialEmployeeDuties = [];
  String? _initialApproverId;
  DateTime? _initialDutyDate;
  TimeOfDay? _initialStartTime;
  TimeOfDay? _initialEndTime;
  String? _initialTransport;
  bool _initialIsRejected = false;
  String? _initialRejectionReason;

  final TextStyle _labelStyle = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  final TextStyle _inputStyle = const TextStyle(
    fontSize: 16,
  );

  final _formKey = GlobalKey<FormState>();

  bool get isEditing => widget.dutyToEdit != null;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  /// Fetches data needed to populate the form.
  /// - In "create" mode: calls `createDuty` to get lists of employees, approvers, etc.
  /// - In "edit" mode: calls `fetchDutyDetailById` to get existing duty + petugas,
  ///   but also calls `createDuty` to fetch the master lists.
  Future<void> _initializeForm() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final User user = await _authService.loadUserInfo();
      if (!mounted) return;

      // Always fetch "create duty" for the master lists
      final BaseResponse<CreateDutyResponse> createDutyResponse =
          await _apiService.createDuty(
        nik: user.nik,
        orgeh: user.orgeh,
        ba: user.ba,
      );

      if (createDutyResponse.metadata.code != 200) {
        throw Exception(createDutyResponse.metadata.message);
      }

      // Master lists
      _employeeList = createDutyResponse.response.employee; 
      _approverList = createDutyResponse.response.approver;
      _transportList = createDutyResponse.response.transport;

      if (isEditing) {
        // If we're editing an existing duty, fetch the duty detail from the /show endpoint
        final int dutyId = widget.dutyToEdit!.id;
        final dutyDetailResp =
            await _apiService.fetchDutyDetailById(dutyId, user);
        if (!mounted) return;

        if (dutyDetailResp.metadata.code == 200) {
          final GetDutyDetail detailData = dutyDetailResp.response;

          // Fill in existing duty data
          final duty = detailData.duty;
          _description = duty.description ?? "";
          // Check if duty is "rejected"
          isRejected = duty.status == DutyStatus.rejected.code;

          // Approver
          _selectedApproverId = widget.approvalToEdit?.nik;

          // Date/Time
          _selectedDutyDate = duty.dutyDate;
          _startTime = _parseTime(duty.startTime);
          _endTime = _parseTime(duty.endTime);
          _selectedTransport = duty.transport; // "1" or "2"

          // If the duty was previously rejected, set the reason if available
          // (Adjust if your API provides the reason differently)
          // e.g.: _rejectionReason = detailData.rejectionReason ?? "";

          // Petugas array from the detail (list of NIKs)
          // We assume the server might return "4163" or "00004163".
          // We'll pad to 8 digits to match the employee list if it uses "00004163".
          if (detailData.petugas != null && detailData.petugas!.isNotEmpty) {
            _employeeDuties = detailData.petugas!.map((rawNik) {
              final paddedNik = rawNik.padLeft(8, '0');
              final employeeName = _employeeList[paddedNik] ?? paddedNik;
              return EmployeeDuty(
                employeeId: paddedNik,
                employeeName: employeeName,
              );
            }).toList();
          } else {
            // If none, at least keep one empty row
            _employeeDuties = [
              EmployeeDuty(employeeId: "", employeeName: ""),
            ];
          }

          // Store initial data for "reset"
          _initialDescription = _description;
          _initialEmployeeDuties = List<EmployeeDuty>.from(_employeeDuties);
          _initialApproverId = _selectedApproverId;
          _initialDutyDate = _selectedDutyDate;
          _initialStartTime = _startTime;
          _initialEndTime = _endTime;
          _initialTransport = _selectedTransport;
          _initialIsRejected = isRejected;
          _initialRejectionReason = _rejectionReason;
        } else {
          throw Exception(dutyDetailResp.metadata.message);
        }
      } else {
        // "Create" mode (no duty to edit)
        _initialDescription = "";
        _initialEmployeeDuties = [
          EmployeeDuty(employeeId: "", employeeName: ""),
        ];
        _initialApproverId = null;
        _initialDutyDate = null;
        _initialStartTime = null;
        _initialEndTime = null;
        _initialTransport = null;
        _initialIsRejected = false;
        _initialRejectionReason = null;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? 'Failed to load form data.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  /// Validate the form fields
  bool _validateForm() {
    if (_description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a description.")),
      );
      return false;
    }

    // Check if at least one employee is selected
    for (var entry in _employeeDuties) {
      if (entry.employeeId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select an employee.")),
        );
        return false;
      }
    }

    // Check if approver is selected
    if (_selectedApproverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an approver.")),
      );
      return false;
    }

    // Check if duty date is selected
    if (_selectedDutyDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a duty date.")),
      );
      return false;
    }

    // Check if start and end times are selected
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select start and end times.")),
      );
      return false;
    }

    // Check if transport is selected
    if (_selectedTransport == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a transport option.")),
      );
      return false;
    }

    return true;
  }

  /// Create or Update (Save as Draft)
  void _saveOrUpdateForm() async {
    if (!_validateForm()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final user = await _authService.loadUserInfo();
      if (!mounted) return;

      // Prepare the employee map: { "0": "00004163", "1": "00004199", ... }
      final Map<String, String> employeeMap = {};
      for (int i = 0; i < _employeeDuties.length; i++) {
        if (_employeeDuties[i].employeeId.isNotEmpty) {
          employeeMap["$i"] = _employeeDuties[i].employeeId;
        }
      }

      // Build the request body
      final Map<String, dynamic> requestBody = {
        "wkt_mulai": _timeToString(_startTime) ?? "09:00",
        "wkt_selesai": _timeToString(_endTime) ?? "17:00",
        "tgl_tugas": _selectedDutyDate != null
            ? DateFormat('yyyy-MM-dd').format(_selectedDutyDate!)
            : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "keterangan": _description,
        "kendaraan": int.tryParse(_selectedTransport ?? '0') ?? 0,
        "employee": employeeMap,
        "nik": user.nik,
        "username": user.username,
        "approver": _selectedApproverId ?? '',
        "submit": "save", // 'save' = draft, 'submit' = send to approver
      };

      if (isEditing) {
        // Update existing duty
        final int dutyId = widget.dutyToEdit!.id;
        final BaseResponse<String> response =
            await _apiService.updateDuty(dutyId, requestBody);

        if (!mounted) return;
        if (response.metadata.code == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.response ?? 'Duty updated successfully.')),
          );
          Navigator.pop(context, 'updated');
        } else {
          throw Exception(response.metadata.message ?? 'Failed to update duty.');
        }
      } else {
        // Create new duty
        final BaseResponse<String> response =
            await _apiService.storeDuty(requestBody);

        if (!mounted) return;
        if (response.metadata.code == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.response ?? 'Duty created successfully.')),
          );
          Navigator.pop(context, 'saved');
        } else {
          throw Exception(response.metadata.message ?? 'Failed to create duty.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? 'An error occurred.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  /// Send to Approver => changes status to Waiting
  void _sendToApprover() async {
    if (!_validateForm()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final user = await _authService.loadUserInfo();
      if (!mounted) return;

      // Prepare the employee map
      final Map<String, String> employeeMap = {};
      for (int i = 0; i < _employeeDuties.length; i++) {
        if (_employeeDuties[i].employeeId.isNotEmpty) {
          employeeMap["$i"] = _employeeDuties[i].employeeId;
        }
      }

      final Map<String, dynamic> requestBody = {
        "wkt_mulai": _timeToString(_startTime) ?? "09:00",
        "wkt_selesai": _timeToString(_endTime) ?? "17:00",
        "tgl_tugas": _selectedDutyDate != null
            ? DateFormat('yyyy-MM-dd').format(_selectedDutyDate!)
            : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "keterangan": _description,
        "kendaraan": int.tryParse(_selectedTransport ?? '0') ?? 0,
        "employee": employeeMap,
        "nik": user.nik,
        "username": user.username,
        "approver": _selectedApproverId ?? '',
        "submit": "submit", // 'submit' = send to approver
      };

      if (isEditing) {
        final int dutyId = widget.dutyToEdit!.id;
        final BaseResponse<String> response =
            await _apiService.updateDuty(dutyId, requestBody);

        if (!mounted) return;
        if (response.metadata.code == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.response ?? 'Duty sent to approver.')),
          );
          Navigator.pop(context, 'sent');
        } else {
          throw Exception(response.metadata.message ?? 'Failed to send duty.');
        }
      } else {
        final BaseResponse<String> response =
            await _apiService.storeDuty(requestBody);

        if (!mounted) return;
        if (response.metadata.code == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.response ?? 'Duty sent to approver.')),
          );
          Navigator.pop(context, 'sent');
        } else {
          throw Exception(response.metadata.message ?? 'Failed to send duty.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? 'An error occurred.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  /// Converts TimeOfDay to "HH:mm" string
  String? _timeToString(TimeOfDay? time) {
    if (time == null) return null;
    final hourStr = time.hour.toString().padLeft(2, '0');
    final minStr = time.minute.toString().padLeft(2, '0');
    return "$hourStr:$minStr";
  }

  /// Parses "HH:mm" from Duty model into TimeOfDay
  TimeOfDay? _parseTime(String? time) {
    if (time == null || time.isEmpty) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Reset form to initial values
  void _resetForm() {
    setState(() {
      _employeeDuties = List<EmployeeDuty>.from(_initialEmployeeDuties);
      _description = _initialDescription;
      _selectedApproverId = _initialApproverId;
      _selectedDutyDate = _initialDutyDate;
      _startTime = _initialStartTime;
      _endTime = _initialEndTime;
      _selectedTransport = _initialTransport;
      isRejected = _initialIsRejected;
      _rejectionReason = _initialRejectionReason;
      _selectedAction = null;
    });
  }

  /// Renders a single employee row with a *searchable* dropdown & remove button
  Widget _buildEmployeeRow(int index) {
    final employeeDuty = _employeeDuties[index];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            // Use DropdownSearch for employee selection
            Expanded(
              child: DropdownSearch<String>(
                items: _employeeList.values.toList(),
                selectedItem: employeeDuty.employeeName.isNotEmpty
                    ? employeeDuty.employeeName
                    : null,
                enabled: !isRejected,
                dropdownDecoratorProps: const DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: "Search or Select Employee",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 16.0,
                    ),
                  ),
                ),
                popupProps: const PopupProps.menu(
                  showSearchBox: true,
                ),
                onChanged: (String? name) {
                  if (name != null) {
                    // Find the matching key from _employeeList
                    final matchedEntry = _employeeList.entries.firstWhere(
                      (e) => e.value == name,
                      orElse: () => const MapEntry("", ""),
                    );
                    setState(() {
                      _employeeDuties[index] = EmployeeDuty(
                        employeeId: matchedEntry.key,
                        employeeName: matchedEntry.value,
                      );
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            // Remove button if more than 1 row and not rejected
            if (_employeeDuties.length > 1 && !isRejected)
              IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _employeeDuties.removeAt(index);
                  });
                },
                tooltip: "Remove Employee",
              ),
          ],
        ),
      ),
    );
  }

  /// Adds a new row for selecting additional employees
  void _addEmployeeField() {
    if (!isRejected) {
      setState(() {
        _employeeDuties.add(EmployeeDuty(employeeId: "", employeeName: ""));
      });
    }
  }

  /// Build the "Rejection Reason" section (if needed)
  Widget _buildRejectionReason() {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Rejection Reason:",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (_rejectionReason?.isNotEmpty ?? false)
                ? _rejectionReason!
                : "No reason provided.",
            style: const TextStyle(
              color: Colors.red,
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the list of possible actions in the dropdown
  List<DropdownMenuItem<String>> _getActionDropdownItems(bool isEditing) {
    // "Reset" is always available
    List<String> actions = ['Reset'];
    if (isEditing) {
      actions.addAll(['Update', 'Send to Approver']);
    } else {
      actions.addAll(['Save', 'Send to Approver']);
    }
    return actions
        .map((action) => DropdownMenuItem<String>(
              value: action,
              child: Text(action),
            ))
        .toList();
  }

  /// Get appropriate button color for the selected action
  Color _getButtonColor(String? action) {
    switch (action) {
      case 'Reset':
        return Colors.redAccent;
      case 'Save':
      case 'Update':
        return Colors.blue;
      case 'Send to Approver':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Duty" : "Create Duty"),
        backgroundColor: Colors.teal,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------- EMPLOYEE SELECTION --------
                        const Text(
                          "Employees:",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _employeeDuties.length,
                          itemBuilder: (context, index) =>
                              _buildEmployeeRow(index),
                        ),
                        const SizedBox(height: 10),
                        // "+" Button to add more employees
                        Center(
                          child: IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.teal,
                              size: 30,
                            ),
                            onPressed: isRejected ? null : _addEmployeeField,
                            tooltip: "Add Employee",
                          ),
                        ),
                        const SizedBox(height: 20),

                        // -------- DESCRIPTION --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Description:", style: _labelStyle),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: _description,
                          onChanged: isRejected
                              ? null
                              : (val) {
                                  setState(() {
                                    _description = val;
                                  });
                                },
                          decoration: const InputDecoration(
                            labelText: "Enter Description",
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 16.0,
                            ),
                          ),
                          maxLines: 3,
                          enabled: !isRejected,
                        ),
                        // Show old description if editing & changed
                        if (isEditing &&
                            _initialDescription.isNotEmpty &&
                            _initialDescription != _description)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Previous: $_initialDescription",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),

                        // -------- APPROVER (SEARCHABLE) --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Approver:", style: _labelStyle),
                        ),
                        const SizedBox(height: 8),
                        DropdownSearch<String>(
                          items: _approverList.values.toList(),
                          selectedItem: (_selectedApproverId != null &&
                                  _approverList[_selectedApproverId!] != null)
                              ? _approverList[_selectedApproverId!]
                              : null,
                          enabled: !isRejected,
                          dropdownDecoratorProps: const DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              labelText: "Search or Select Approver",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 16.0,
                              ),
                            ),
                          ),
                          popupProps: const PopupProps.menu(
                            showSearchBox: true,
                          ),
                          onChanged: (String? name) {
                            if (name != null) {
                              // Find the matching key from _approverList
                              final matchedEntry = _approverList.entries.firstWhere(
                                (e) => e.value == name,
                                orElse: () => const MapEntry("", ""),
                              );
                              setState(() {
                                _selectedApproverId = matchedEntry.key;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 20),

                        // -------- DUTY DATE --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Duty Date:", style: _labelStyle),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: isRejected ? null : _pickDate,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.teal.shade50,
                            ),
                            child: Text(
                              _selectedDutyDate == null
                                  ? "Select Date"
                                  : DateFormat('dd-MM-yyyy')
                                      .format(_selectedDutyDate!),
                              style: _inputStyle.copyWith(
                                color: Colors.teal.shade800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // -------- START & END TIME --------
                        Row(
                          children: [
                            // Start Time
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Start Time:", style: _labelStyle),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: isRejected
                                        ? null
                                        : () => _pickTime(isStart: true),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.teal.shade50,
                                      ),
                                      child: Text(
                                        _startTime == null
                                            ? "HH:MM"
                                            : _formatTime(_startTime),
                                        style: _inputStyle.copyWith(
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isEditing &&
                                      _initialStartTime != null &&
                                      _initialStartTime != _startTime)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        "Previous: ${_formatTime(_initialStartTime)}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            // End Time
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("End Time:", style: _labelStyle),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: isRejected
                                        ? null
                                        : () => _pickTime(isStart: false),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.teal.shade50,
                                      ),
                                      child: Text(
                                        _endTime == null
                                            ? "HH:MM"
                                            : _formatTime(_endTime),
                                        style: _inputStyle.copyWith(
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isEditing &&
                                      _initialEndTime != null &&
                                      _initialEndTime != _endTime)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        "Previous: ${_formatTime(_initialEndTime)}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // -------- TRANSPORT --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Transport:", style: _labelStyle),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedTransport,
                          items: _transportList.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: isRejected
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedTransport = value;
                                  });
                                },
                          decoration: const InputDecoration(
                            labelText: "Select Transport",
                            border: OutlineInputBorder(),
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 12.0),
                          ),
                        ),
                        if (isEditing &&
                            _initialTransport != null &&
                            _initialTransport != _selectedTransport)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Previous: ${_transportList[_initialTransport] ?? "Not Set"}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 30),

                        // -------- REJECTION REASON (IF REJECTED) --------
                        if (isRejected) _buildRejectionReason(),

                        // -------- ACTION DROPDOWN & SUBMIT BUTTON --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Action:", style: _labelStyle),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Action Dropdown
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedAction,
                                hint: const Text("Select Action"),
                                items: _getActionDropdownItems(isEditing),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedAction = value;
                                  });
                                },
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 12.0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            // Submit Button
                            ElevatedButton(
                              onPressed: _selectedAction == null || isLoading
                                  ? null
                                  : () {
                                      switch (_selectedAction) {
                                        case 'Reset':
                                          _resetForm();
                                          break;
                                        case 'Save':
                                        case 'Update':
                                          _saveOrUpdateForm();
                                          break;
                                        case 'Send to Approver':
                                          _sendToApprover();
                                          break;
                                        default:
                                          break;
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _getButtonColor(_selectedAction),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _selectedAction == 'Update'
                                          ? "Update"
                                          : _selectedAction == 'Send to Approver'
                                              ? "Send to Approver"
                                              : _selectedAction == 'Reset'
                                                  ? "Reset"
                                                  : "Submit",
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
      bottomNavigationBar: const CustomBottomAppBar(),
    );
  }

  /// Simple utility to format a TimeOfDay as "hh:mm a" for UI
  String _formatTime(TimeOfDay? time) {
    if (time == null) return "HH:MM";
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt); // e.g., "06:00 AM"
  }

  /// Show date picker
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _selectedDutyDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              onSurface: Colors.teal,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.teal,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        _selectedDutyDate = result;
      });
    }
  }

  /// Show time picker
  Future<void> _pickTime({required bool isStart}) async {
    final now = TimeOfDay.now();
    final result = await showTimePicker(
      context: context,
      initialTime: isStart ? (_startTime ?? now) : (_endTime ?? now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              onSurface: Colors.teal,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.teal),
            ),
          ),
          child: child!,
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = result;
        } else {
          _endTime = result;
        }
      });
    }
  }
}
