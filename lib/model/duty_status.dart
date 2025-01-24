// lib/model/duty_status.dart

import 'package:flutter/material.dart';

enum DutyStatus {
  waiting("1", "Waiting", "Needs Approval"),
  approved("2", "Approved", "Approve"),
  returned("3", "Returned", "Return"),
  draft("4", "Draft", ""), // Selesai atau Draft?
  rejected("5", "Rejected", "Reject");

  // 1: dikirim
  // 2: disetujui
  // 3: dikembalikan
  // 4: selesai
  // 5: ditolak

  final String code;
  final String makerDesc;
  final String approverDesc;

  const DutyStatus(this.code, this.makerDesc, this.approverDesc);

  /// Finds a DutyStatus by its code.
  static DutyStatus fromCode(String? code) {
    if (code == null) return DutyStatus.draft;
    return DutyStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => DutyStatus.draft, // Default fallback
    );
  }

  /// Returns the associated color for each DutyStatus.
  Color get color {
    switch (this) {
      case DutyStatus.draft:
        return Colors.grey;
      case DutyStatus.waiting:
        return Colors.orange;
      case DutyStatus.approved:
        return Colors.green;
      case DutyStatus.returned:
        return Colors.purple;
      case DutyStatus.rejected:
        return Colors.red;
      default:
        return Colors.grey; // Fallback color
    }
  }
}
