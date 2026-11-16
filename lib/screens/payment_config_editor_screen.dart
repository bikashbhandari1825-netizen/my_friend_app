// screens/payment_config_editor_screen.dart
// Admin (Owner Dashboard) ले commission % र gateway (eSewa/Khalti/
// Bank-ConnectIPS) credential/enabled-toggle कुनै नयाँ app release बिनै
// सिधै सम्पादन गर्ने ठाउँ — Firestore: config/payments (हेर्नुहोस्
// config/app_config.dart::PaymentConfig)। `FareMatrixEditorScreen` कै उही
// ढाँचा। Save गर्नेबित्तिकै यही app-instance (admin आफैं) कै cache तुरुन्तै
// अपडेट हुन्छ; अरू सबै device (worker/employer) ले `main.dart` कै startup
// live listener (`PaymentConfig.preload`) मार्फत केही सेकेन्डभित्रै पाउँछन्
// — कसैले पनि app फेरि restart/re-install गर्नु पर्दैन। कुनै gateway अझै
// साँचो merchant नभएकोले "Enabled" off गरे, `complete_job_sheet.dart` को
// checkout selector मा त्यसको कार्ड नै देखिँदैन (worker/employer लाई अझै
// तयार नभएको विकल्प कहिल्यै देखिँदैन)।
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class PaymentConfigEditorScreen extends StatefulWidget {
  const PaymentConfigEditorScreen({super.key});

  @override
  State<PaymentConfigEditorScreen> createState() =>
      _PaymentConfigEditorScreenState();
}

class _PaymentConfigEditorScreenState
    extends State<PaymentConfigEditorScreen> {
  bool _loading = true;
  bool _saving = false;

  final _commissionCtrl = TextEditingController();
  final _minimumWalletThresholdCtrl = TextEditingController();
  final _esewaMerchantCtrl = TextEditingController();
  final _khaltiMerchantCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccountNameCtrl = TextEditingController();
  final _bankAccountNumberCtrl = TextEditingController();
  final _connectIpsCtrl = TextEditingController();

  bool _esewaEnabled = true;
  bool _khaltiEnabled = true;
  bool _bankEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commissionCtrl.dispose();
    _minimumWalletThresholdCtrl.dispose();
    _esewaMerchantCtrl.dispose();
    _khaltiMerchantCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountNameCtrl.dispose();
    _bankAccountNumberCtrl.dispose();
    _connectIpsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await PaymentConfig.readOnce();
    final rate = (data['commissionRate'] as num?)?.toDouble() ??
        PaymentConfig.defaultCommissionRate;
    _commissionCtrl.text = (rate * 100).toStringAsFixed(0);
    final threshold = (data['minimumWalletThreshold'] as num?)?.toDouble() ??
        PaymentConfig.defaultMinimumWalletThreshold;
    _minimumWalletThresholdCtrl.text = threshold.toStringAsFixed(0);
    _esewaEnabled = (data['esewaEnabled'] as bool?) ?? true;
    _khaltiEnabled = (data['khaltiEnabled'] as bool?) ?? true;
    _bankEnabled = (data['bankEnabled'] as bool?) ?? true;
    _esewaMerchantCtrl.text = (data['esewaMerchantId'] ?? '').toString();
    _khaltiMerchantCtrl.text = (data['khaltiMerchantId'] ?? '').toString();
    _bankNameCtrl.text = (data['bankName'] ?? '').toString();
    _bankAccountNameCtrl.text = (data['bankAccountName'] ?? '').toString();
    _bankAccountNumberCtrl.text = (data['bankAccountNumber'] ?? '').toString();
    _connectIpsCtrl.text = (data['connectIpsId'] ?? '').toString();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final pct = double.tryParse(_commissionCtrl.text.trim()) ??
          (PaymentConfig.defaultCommissionRate * 100);
      final threshold = double.tryParse(_minimumWalletThresholdCtrl.text.trim()) ??
          PaymentConfig.defaultMinimumWalletThreshold;
      await PaymentConfig.setPaymentSettings(
        commissionRate: (pct / 100).clamp(0, 1).toDouble(),
        minimumWalletThreshold: threshold,
        esewaEnabled: _esewaEnabled,
        esewaMerchantId: _esewaMerchantCtrl.text.trim(),
        khaltiEnabled: _khaltiEnabled,
        khaltiMerchantId: _khaltiMerchantCtrl.text.trim(),
        bankEnabled: _bankEnabled,
        bankName: _bankNameCtrl.text.trim(),
        bankAccountName: _bankAccountNameCtrl.text.trim(),
        bankAccountNumber: _bankAccountNumberCtrl.text.trim(),
        connectIpsId: _connectIpsCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController ctrl,
          {TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.kmText),
          decoration: kmInputDecoration(label),
        ),
      );

  Widget _gatewayToggle(String title, IconData icon, Gradient grad,
          bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: KmListTile(
          icon: icon,
          iconBg: grad,
          title: title,
          subtitle: value ? 'Shown to users at checkout' : 'Hidden — disabled',
          trailing: Switch(
            value: value,
            activeThumbColor: AppColors.kmOrange,
            onChanged: onChanged,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(
                  title: 'Payment & Commission',
                  actions: [
                    GlassIconButton(
                      icon: Icons.save_rounded,
                      tooltip: 'Save',
                      onTap: _saving || _loading ? null : _save,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.kmOrange))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        children: [
                          const KmSectionLabel('Platform commission'),
                          _field('Commission rate', _commissionCtrl,
                              keyboardType: TextInputType.number),
                          const Text(
                            'Percentage the platform keeps from every '
                            'completed job — online payments settle it '
                            'directly, cash jobs record it as an amount '
                            'the driver owes on their wallet ledger.',
                            style: TextStyle(
                                color: AppColors.kmMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          const KmSectionLabel('Driver wallet'),
                          _field('Minimum wallet threshold',
                              _minimumWalletThresholdCtrl,
                              keyboardType: TextInputType.number),
                          const Text(
                            'Drivers are blocked from new jobs once their '
                            'unsettled cash/QR commission debt exceeds this '
                            'amount — they stay eligible while only owed a '
                            'payout, and become eligible again as soon as '
                            'an admin settles them below this line.',
                            style: TextStyle(
                                color: AppColors.kmMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          const KmSectionLabel('Gateways at checkout'),
                          _gatewayToggle(
                              'eSewa',
                              Icons.account_balance_wallet_rounded,
                              const LinearGradient(
                                  colors: [Color(0xFF60BB46), Color(0xFF3F8A2C)]),
                              _esewaEnabled,
                              (v) => setState(() => _esewaEnabled = v)),
                          _field('eSewa merchant ID', _esewaMerchantCtrl),
                          const SizedBox(height: 8),
                          _gatewayToggle(
                              'Khalti',
                              Icons.account_balance_wallet_rounded,
                              const LinearGradient(
                                  colors: [Color(0xFF5C2D91), Color(0xFF3D1D63)]),
                              _khaltiEnabled,
                              (v) => setState(() => _khaltiEnabled = v)),
                          _field('Khalti merchant ID', _khaltiMerchantCtrl),
                          const SizedBox(height: 8),
                          _gatewayToggle(
                              'Bank / ConnectIPS',
                              Icons.account_balance_rounded,
                              const LinearGradient(
                                  colors: [Color(0xFF1E5AA8), Color(0xFF123B70)]),
                              _bankEnabled,
                              (v) => setState(() => _bankEnabled = v)),
                          _field('Bank name', _bankNameCtrl),
                          _field('Account holder name', _bankAccountNameCtrl),
                          _field('Account number', _bankAccountNumberCtrl,
                              keyboardType: TextInputType.number),
                          _field('ConnectIPS merchant ID', _connectIpsCtrl),
                          const SizedBox(height: 24),
                          KmCtaButton(
                            label: _saving ? 'Saving…' : 'Save',
                            icon: Icons.save_rounded,
                            loading: _saving,
                            onPressed: _saving ? null : _save,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
