// lib/dto/get_duty_detail.dart

import 'package:mobileapp/model/approval.dart';
import 'package:mobileapp/model/duty.dart';

class GetDutyDetail {
  /// Duty detail information
  final Duty duty;

  /// Transport options (e.g. { "1": "Disediakan Perusahaan", "2": "Kendaraan Pribadi" })
  final Map<String, String> transport;

  /// Approver list returned by the API
  final Map<String, String> approverList;

  /// Employee list returned by the API
  final Map<String, String> employeeList;

  /// Single approver object if present
  final Approval? approver;

  /// Removed `final` to allow reassignment later if needed
  Approval? position;

  /// New field for storing array of NIKs (IDs) for the assigned employees/petugas
  List<String>? petugas;

  GetDutyDetail({
    required this.duty,
    required this.transport,
    required this.approverList,
    required this.employeeList,
    this.approver,
    this.position,
    this.petugas,
  });

  factory GetDutyDetail.fromJson(Map<String, dynamic> json) {
    // Safely retrieve each field from the JSON
    final dutyJson = json['duty'] ?? {};
    final approverJson = json['approver'];
    final positionJson = json['position'];
    final transportJson = json['transport'] ?? {};
    final approverListJson = json['approver_list'] ?? {};
    final employeeListJson = json['employee_list'] ?? {};

    // Parse the main Duty object
    final dutyObj = Duty.fromJson(dutyJson);

    // Parse optional Approval objects
    final approvalObj = (approverJson != null) ? Approval.fromJson(approverJson) : null;
    final positionObj = (positionJson != null) ? Approval.fromJson(positionJson) : null;

    // Cast or convert maps to Map<String, String>
    final transportMap = Map<String, String>.from(
      (transportJson as Map<String, dynamic>?) ?? {},
    );
    final approverMap = Map<String, String>.from(
      (approverListJson as Map<String, dynamic>?) ?? {},
    );
    final employeeMap = Map<String, String>.from(
      (employeeListJson as Map<String, dynamic>?) ?? {},
    );

    // Parse the petugas array if present (List of NIKs)
    List<String>? petugasList;
    if (json['petugas'] != null && json['petugas'] is List) {
      petugasList = (json['petugas'] as List<dynamic>)
          .map((item) => item.toString())
          .toList();
    }

    return GetDutyDetail(
      duty: dutyObj,
      transport: transportMap,
      approverList: approverMap,
      employeeList: employeeMap,
      approver: approvalObj,
      position: positionObj,
      petugas: petugasList,
    );
  }
}
