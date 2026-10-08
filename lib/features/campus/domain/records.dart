import 'json_fields.dart';

class StudentProfile {
  const StudentProfile({
    required this.studentId,
    required this.name,
    this.college = '',
    this.major = '',
    this.className = '',
    this.grade = '',
    this.gender = '',
  });
  final String studentId, name, college, major, className, grade, gender;
  factory StudentProfile.fromJson(Json json) => StudentProfile(
    studentId: textValue(json['studentId'], required: true),
    name: textValue(json['name'], required: true),
    college: textValue(json['college']),
    major: textValue(json['major']),
    className: textValue(json['className']),
    grade: textValue(json['grade']),
    gender: textValue(json['gender']),
  );
}

class ScheduleCourse {
  const ScheduleCourse({
    this.day = '',
    this.slot = '',
    required this.title,
    this.teacher = '',
    this.weeks = '',
    this.sections = '',
    this.location = '',
  });
  final String day, slot, title, teacher, weeks, sections, location;
  factory ScheduleCourse.fromJson(Json json) => ScheduleCourse(
    day: textValue(json['day']),
    slot: textValue(json['slot']),
    title: textValue(json['title'], required: true),
    teacher: textValue(json['teacher']),
    weeks: textValue(json['weeks']),
    sections: textValue(json['sections']),
    location: textValue(json['location']),
  );
}

class Grade {
  const Grade({
    this.term = '',
    this.courseCode = '',
    required this.courseName,
    this.score = '',
    this.credit = '',
    this.gradePoint = '',
    this.examNature = '',
    this.source = '',
    this.makeupTerm = '',
    this.scoreFlag = '',
  });
  final String term,
      courseCode,
      courseName,
      score,
      credit,
      gradePoint,
      examNature,
      source,
      makeupTerm,
      scoreFlag;
  factory Grade.fromJson(Json json) => Grade(
    term: textValue(json['term']),
    courseCode: textValue(json['courseCode']),
    courseName: textValue(json['courseName'], required: true),
    score: textValue(json['score']),
    credit: textValue(json['credit']),
    gradePoint: textValue(json['gradePoint']),
    examNature: textValue(json['examNature']),
    source: textValue(json['source']),
    makeupTerm: textValue(json['makeupTerm']),
    scoreFlag: textValue(json['scoreFlag']),
  );
  double? get numericScore => optionalNumber(score);
  double? get numericCredit => optionalNumber(credit);
  double? get numericGradePoint => optionalNumber(gradePoint);
}

class Exam {
  const Exam({
    required this.courseName,
    this.teacher = '',
    this.examTime = '',
    this.examPlace = '',
    this.seatNo = '',
    this.courseCode = '',
    this.examSession = '',
    this.campus = '',
  });
  final String courseName,
      teacher,
      examTime,
      examPlace,
      seatNo,
      courseCode,
      examSession,
      campus;
  factory Exam.fromJson(Json json) => Exam(
    courseName: textValue(json['courseName'], required: true),
    teacher: textValue(json['teacher']),
    examTime: textValue(json['examTime']),
    examPlace: textValue(json['examPlace']),
    seatNo: textValue(json['seatNo']),
    courseCode: textValue(json['courseCode']),
    examSession: textValue(json['examSession']),
    campus: textValue(json['campus']),
  );
}

class TrainingRecord {
  const TrainingRecord({
    this.graduationYear = '',
    this.graduationType = '',
    this.graduationConclusion = '',
    this.graduationTime = '',
    this.certificateNo = '',
  });
  final String graduationYear,
      graduationType,
      graduationConclusion,
      graduationTime,
      certificateNo;
  factory TrainingRecord.fromJson(Json json) => TrainingRecord(
    graduationYear: textValue(json['graduationYear']),
    graduationType: textValue(json['graduationType']),
    graduationConclusion: textValue(json['graduationConclusion']),
    graduationTime: textValue(json['graduationTime']),
    certificateNo: textValue(json['certificateNo']),
  );
}

class CardAccount {
  const CardAccount({
    this.typeCode = '',
    this.typeName = '',
    required this.balance,
    this.unit = '',
  });
  final String typeCode, typeName, balance, unit;
  factory CardAccount.fromJson(Json json) => CardAccount(
    typeCode: textValue(json['typeCode']),
    typeName: textValue(json['typeName']),
    balance: textValue(json['balance'], required: true),
    unit: textValue(json['unit']),
  );
}

class CardTransaction {
  const CardTransaction({
    this.date = '',
    this.summary = '',
    this.merchantName = '',
    required this.amount,
    this.isRefund = '',
    this.journo = '',
    this.operation = false,
  });
  final String date, summary, merchantName, amount, isRefund, journo;
  final bool operation;
  factory CardTransaction.fromJson(Json json) => CardTransaction(
    date: textValue(json['date']),
    summary: textValue(json['summary']),
    merchantName: textValue(json['merchantName']),
    amount: textValue(json['amount'], required: true),
    isRefund: textValue(json['isRefund']),
    journo: textValue(json['journo']),
    operation: boolValue(json['operation']),
  );
}

class DormRoom {
  const DormRoom({
    required this.query,
    this.buildingName = '',
    this.levelName = '',
    this.roomName = '',
  });
  final String query, buildingName, levelName, roomName;
  factory DormRoom.fromJson(Json json) => DormRoom(
    query: textValue(json['query'], required: true),
    buildingName: textValue(json['buildingName']),
    levelName: textValue(json['levelName']),
    roomName: textValue(json['roomName']),
  );
}

class UtilityAccount {
  const UtilityAccount({
    required this.utilityAccount,
    this.utilityUsername = '',
    this.utilityStatusName = '',
    this.accStatusName = '',
  });
  final String utilityAccount,
      utilityUsername,
      utilityStatusName,
      accStatusName;
  factory UtilityAccount.fromJson(Json json) => UtilityAccount(
    // School accounts may omit this display identifier. Payments are routed
    // using the selected dorm room, not this optional account summary.
    utilityAccount: textValue(json['utilityAccount']),
    utilityUsername: textValue(json['utilityUsername']),
    utilityStatusName: textValue(json['utilityStatusName']),
    accStatusName: textValue(json['accStatusName']),
  );
}

class AmountOption {
  const AmountOption({this.id = '', required this.amount, this.name = ''});
  final String id, amount, name;
  factory AmountOption.fromJson(Json json) => AmountOption(
    id: textValue(json['id']),
    amount: textValue(json['amount'], required: true),
    name: textValue(json['name']),
  );
}
