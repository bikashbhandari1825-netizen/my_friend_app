// widgets/country_phone_field.dart
// साझा फोन-नम्बर Form फिल्ड — देश-कोड picker (`country_picker`, phone_input_
// page.dart मै प्रयोग भइरहेको उही package) लाई TextFormField कै prefixIcon
// भित्र embed गर्ने। Controller मा राष्ट्रिय अंक मात्र रहन्छ — पूरा E.164
// चाहिँदा submit बेला `resolveE164(country, controller.text)`
// (auth/phone_format.dart) बोलाउनुहोस्।
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CountryPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final Country country;
  final ValueChanged<Country> onCountryChanged;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final TextStyle? style;

  const CountryPhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    required this.decoration,
    this.validator,
    this.style,
  });

  void _pick(BuildContext context) {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['NP', 'IN'],
      onSelect: onCountryChanged,
      countryListTheme: CountryListThemeData(
        backgroundColor: AppColors.kmSurface,
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.82,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        textStyle: const TextStyle(color: AppColors.kmText, fontSize: 15),
        searchTextStyle:
            const TextStyle(color: AppColors.kmText, fontSize: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: style,
      validator: validator,
      decoration: decoration.copyWith(
        prefixIcon: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(country.flagEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 4),
                Text('+${country.phoneCode}',
                    style: style ??
                        const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded,
                    size: 16, color: AppColors.kmMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
