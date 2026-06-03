enum XjitFeature {
  profile('jw.profile', '个人信息'),
  schedule('jw.schedule', '课表'),
  grades('jw.grades', '成绩'),
  exams('jw.exams', '考试'),
  training('jw.training', '培养信息'),
  cardBalance('newcard.balance', '校园卡余额'),
  cardTransactions('newcard.transactions', '校园卡流水'),
  campusPaymentCode('newcard.campus_code.qrcode', '校园付款码'),
  rechargeConfig('newcard.recharge.config', '一卡通充值配置'),
  rechargeCreateOrder('newcard.recharge.create_order', '一卡通充值下单'),
  electricityAccount('newcard.electricity.account', '宿舍电费');

  const XjitFeature(this.value, this.title);

  final String value;
  final String title;
}
