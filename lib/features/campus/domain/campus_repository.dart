import 'academic_models.dart';
import 'card_models.dart';
import 'records.dart';

abstract interface class CampusRepository {
  Future<StudentProfile> profile();
  Future<Schedule> schedule({String? term});
  Future<Grades> grades({
    String? term,
    GradeMode mode = GradeMode.bestByCourse,
  });
  Future<List<Exam>> exams();
  Future<List<TrainingRecord>> training();
  Future<List<CardAccount>> balance();
  Future<TransactionPage> transactions(
    TransactionQuery query, {
    int pageNo = 1,
  });
  Future<CampusCode> campusCode({String qrcodeType = '', String? devCode});
  Future<CardRechargeConfig> cardRechargeConfig();
  Future<PaymentOrder> createCardOrder({
    required MoneyAmount amount,
    required PayMethod method,
    String? otherStudentId,
    Uri? returnUrl,
    String? subOpenId,
    String? subAppId,
    Uri? signReturnUrl,
  });
  Future<ElectricityAccount> electricity(String roomQuery);
  Future<ElectricityRechargeConfig> electricityRechargeConfig(String roomQuery);
  Future<PaymentOrder> payElectricity({
    required String roomQuery,
    required MoneyAmount amount,
    required PayMethod method,
    String? paymentPassword,
    Uri? returnUrl,
    Map<String, dynamic> customFields = const {},
  });
}
