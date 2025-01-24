// lib/services/api_service_easy_taspen.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobileapp/dto/base_response.dart';
import 'package:mobileapp/dto/create_duty_response.dart';
import 'package:mobileapp/dto/get_duty_detail.dart';
import 'package:mobileapp/dto/get_duty_list.dart';
import 'package:mobileapp/dto/login_response.dart';
import 'package:mobileapp/model/approval.dart';
import 'package:mobileapp/model/duty_status.dart';
import 'package:mobileapp/model/user.dart';

class ApiService {
  final String baseUrl =
      "http://localhost:4000/?target=https://apigw.taspen.co.id";

  // ------------------- COMMON HEADERS -------------------
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'x-Gateway-APIKey': 'dce74dd6-33c9-4a84-8948-e65cc02f9d90',
    };
  }

  // ------------------- LOGIN -------------------
  Future<LoginResponse> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/gateway/loginAD/1.0/ApiLoginADPublic');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid response: Expected JSON object');
        }
        final responseBody = decoded;

        // Ensure 'status' key exists in the response
        if (!responseBody.containsKey('status')) {
          throw Exception('Invalid response structure: Missing "status" key.');
        }
        // Attach the username to the response for convenience
        responseBody['status']['USERNAME'] = username;
        return LoginResponse.fromJson(responseBody);
      } else {
        // Extract error message from response if available
        String errorMsg = 'Failed to login: ${response.statusCode}';
        try {
          final dynamic errorDecoded = jsonDecode(response.body);
          if (errorDecoded is Map<String, dynamic>) {
            if (errorDecoded.containsKey('status') &&
                errorDecoded['status'] is Map &&
                errorDecoded['status'].containsKey('TEXT')) {
              errorMsg = errorDecoded['status']['TEXT'];
            }
          }
        } catch (_) {
          // Ignore JSON parsing errors for error responses
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Login Error: $e');
    }
  }

  // ------------------- DUTY LIST -------------------
  Future<BaseResponse<GetDutyList>> fetchDuties(
    String nik,
    String kodeJabatan,
  ) async {
    final url = Uri.parse(
      '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/index',
    );

    try {
      final response = await http.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'nik': nik,
          'kodejabatan': kodeJabatan,
        }),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid duties response: Expected JSON object');
        }
        final responseBody = decoded;

        if (responseBody['metadata']['code'] == 200) {
          return BaseResponse<GetDutyList>.fromJson(
            responseBody,
            (dynamic json) => GetDutyList.fromJson(json),
          );
        } else {
          final msg =
              responseBody['metadata']['message'] ?? 'Failed to fetch duties.';
          throw Exception(msg);
        }
      } else {
        throw Exception('Failed to fetch duties: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching duties: $e');
    }
  }

  // ------------------- DUTY DETAIL -------------------
  Future<BaseResponse<GetDutyDetail>> fetchDutyDetailById(
    int dutyId,
    User user,
  ) async {
    try {
      // 1) Fetch show_edit endpoint
      final urlShowEdit = Uri.parse(
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/$dutyId/show_edit',
      );
      final responseEdit = await http.post(
        urlShowEdit,
        headers: _getHeaders(),
        body: jsonEncode({
          'nik': user.nik,
          'orgeh': user.orgeh,
          'ba': user.ba,
        }),
      );

      // 2) Fetch show endpoint
      final urlShow = Uri.parse(
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/$dutyId/show',
      );
      final responseShow = await http.post(
        urlShow,
        headers: _getHeaders(),
        body: jsonEncode({
          'nik': user.nik,
        }),
      );

      // 3) Check status codes
      if (responseEdit.statusCode == 200 && responseShow.statusCode == 200) {
        final dynamic decodedEdit = jsonDecode(responseEdit.body);
        final dynamic decodedShow = jsonDecode(responseShow.body);

        if (decodedEdit is! Map<String, dynamic> ||
            decodedShow is! Map<String, dynamic>) {
          throw Exception('Duty detail endpoints did not return valid objects.');
        }

        final responseBodyEdit = decodedEdit;
        final responseBodyShow = decodedShow;

        // 4) Validate metadata and response
        if (responseBodyEdit['metadata']?['code'] == 200 &&
            responseBodyEdit['response'] != null &&
            responseBodyShow['response'] != null) {
          // Parse data from show_edit
          final dataEdit = BaseResponse<GetDutyDetail>.fromJson(
            responseBodyEdit,
            (dynamic json) => GetDutyDetail.fromJson(json),
          );

          // Merge data from show endpoint

          // a) Position data
          if (responseBodyShow['response']?['position'] != null) {
            dataEdit.response.position = Approval.fromJson(
              responseBodyShow['response']['position'],
            );
          }

          // b) Petugas (Employee) data => list of NIKs
          if (responseBodyShow['response']?['petugas'] != null) {
            final petugasDynamic = responseBodyShow['response']['petugas'];
            if (petugasDynamic is List) {
              dataEdit.response.petugas =
                  petugasDynamic.map((e) => e.toString()).toList();
            }
          }
          return dataEdit;
        } else {
          final msg = responseBodyEdit['metadata']?['message'] ?? 'Unknown error.';
          throw Exception('Failed to fetch duty: $msg');
        }
      } else {
        throw Exception(
          'Failed to fetch duties: '
          '${responseEdit.statusCode}, ${responseShow.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching duties: $e');
    }
  }

  // ------------------- CREATE DUTY -------------------
  Future<BaseResponse<CreateDutyResponse>> createDuty({
    required String nik,
    required String orgeh,
    required String ba,
  }) async {
    final url = Uri.parse(
      '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/create',
    );

    try {
      final response = await http.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'NIK': nik,
          'ORGEH': orgeh,
          'BA': ba,
        }),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid createDuty response: Expected JSON object');
        }
        final responseBody = decoded;

        if (responseBody['metadata']['code'] == 200) {
          return BaseResponse<CreateDutyResponse>.fromJson(
            responseBody,
            (dynamic json) => CreateDutyResponse.fromJson(json),
          );
        } else {
          final msg = responseBody['metadata']['message'] ??
              'Failed to create duty.';
          throw Exception(msg);
        }
      } else {
        throw Exception('Failed to create duty: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating duty: $e');
    }
  }

  // ------------------- GET MASTER KARYAWAN -------------------
  /// If the endpoint returns an array or object, handle as needed.
  Future<dynamic> getMasterKaryawan() async {
    final url = Uri.parse(
      'http://poprd.taspen.co.id:53000/RESTAdapter/masterkaryawan',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('APPHCIS:Hcisapp1!'))}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        // We don't know if it's a Map or a List, return the raw 'decoded'.
        return decoded;
      } else {
        throw Exception('Failed to fetch karyawan: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // ------------------- STORE DUTY -------------------
  Future<BaseResponse<String>> storeDuty(Map<String, dynamic> requestBody) async {
    final String url =
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/store';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(),
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid storeDuty response: JSON object expected');
        }
        return BaseResponse<String>.fromJson(
          decoded,
          (data) => data as String,
        );
      } else {
        throw Exception('Failed to store duty: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error storing duty: $e');
    }
  }

  // ------------------- UPDATE DUTY -------------------
  Future<BaseResponse<String>> updateDuty(
    int dutyId,
    Map<String, dynamic> requestBody,
  ) async {
    final String url =
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/$dutyId/update';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(),
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid updateDuty response: JSON object expected');
        }
        return BaseResponse<String>.fromJson(
          decoded,
          (data) => data as String,
        );
      } else {
        throw Exception('Failed to update duty: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating duty: $e');
    }
  }

  // ------------------- DELETE DUTY -------------------
  Future<BaseResponse<String>> deleteDuty(int dutyId) async {
    final String url =
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/$dutyId/delete';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid deleteDuty response: JSON object expected');
        }
        return BaseResponse<String>.fromJson(
          decoded,
          (data) => data as String,
        );
      } else {
        throw Exception('Failed to delete duty: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting duty: $e');
    }
  }

  // ------------------- FETCH EMPLOYEES (BOTH ZERO-PADDED & STRIPPED) -------------------
  ///
  /// For each employee key (like "00004163"), we store *both* the original "00004163"
  /// and the stripped version "4163" in the map, mapping to the same name.
  /// This way, if your system references either "00004163" or "4163", we can still find it.
  ///
  Future<Map<String, String>> fetchEmployeesForCreateDuty({
    required String nik,
    required String orgeh,
    required String ba,
  }) async {
    final url = Uri.parse(
      '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/create',
    );
    try {
      final response = await http.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'NIK': nik,
          'ORGEH': orgeh,
          'BA': ba,
        }),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Invalid employees response: JSON object expected');
        }
        final responseBody = decoded;

        // Check metadata code
        if (responseBody['metadata']['code'] == 200) {
          final data = responseBody['response'] ?? {};
          if (data is! Map) {
            throw Exception('Invalid "response" field in employees data.');
          }

          final employeeJson = data['employee'];
          if (employeeJson is! Map) {
            return {};
          }

          /// We store BOTH the original key (e.g. "00004163") AND
          /// the stripped key (e.g. "4163") for the same value.
          final Map<String, String> finalEmployeeMap = {};
          employeeJson.forEach((originalKey, value) {
            final name = value.toString();

            // Keep the original zero-padded key
            finalEmployeeMap[originalKey.toString()] = name;

            // Also store a stripped version (leading zeros removed)
            final stripped = originalKey.toString().replaceFirst(RegExp(r'^0+'), '');
            // Only store if it's not the same as the original
            if (stripped.isNotEmpty && stripped != originalKey) {
              finalEmployeeMap[stripped] = name;
            }
          });

          return finalEmployeeMap;
        } else {
          final message = responseBody['metadata']['message'] ??
              'Failed to fetch employees.';
          throw Exception(message);
        }
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching employees: $e');
    }
  }

  // ------------------- SUBMIT APPROVAL -------------------
  /// This handles both approval (code = 2) **and** rejection (code = 5).
  /// If [status] == DutyStatus.rejected, code=5 => `submit=5` => reject.
  /// If [status] == DutyStatus.approved, code=2 => `submit=2` => approve.
  /// If you have a "return" or "waiting" code, those can be used similarly.
  Future<BaseResponse<Map<String, dynamic>>> submitApproval(
    int dutyId,
    DutyStatus status,
    User user,
    String komentar,
  ) async {
    final String url =
        '$baseUrl/gateway/NewTaspenEasy/1.0/no_token/duty/$dutyId/approval';

    final Map<String, dynamic> bodyReq = {
      "submit": status.code.toString(), // e.g. "2" for approve, "5" for reject
      "kdjabatan": user.kodeJabatan,
      "nik": user.nik,
      "username": user.username,
      "komentar": komentar.isNotEmpty ? komentar : "No comment",
    };

    try {
      print("Submitting approval with body: $bodyReq to $url");
      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(),
        body: json.encode(bodyReq),
      );

      final dynamic decoded = json.decode(response.body);
      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        if (decoded['metadata']['code'] == 200) {
          // "Success" => "SPT berhasil diproses!" possibly
          return BaseResponse<Map<String, dynamic>>.fromJson(
            decoded,
            (data) => data as Map<String, dynamic>,
          );
        } else {
          final errorMessage = decoded['metadata']['message'] ??
              'Error during approval: Unexpected response structure.';
          throw Exception('Approval Error: $errorMessage');
        }
      } else {
        throw Exception(
          'Error submitting approval: Unexpected JSON structure or status code.',
        );
      }
    } catch (e) {
      throw Exception('Error submitting approval: $e');
    }
  }
}
