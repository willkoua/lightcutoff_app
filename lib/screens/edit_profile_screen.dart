import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/geo.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/validators.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _country;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    final home = profile?.homeLocation ?? const GeoArea();
    _firstName = TextEditingController(text: profile?.firstName ?? '');
    _lastName = TextEditingController(text: profile?.lastName ?? '');
    _phone = TextEditingController(text: profile?.phoneNumber ?? '');
    _city = TextEditingController(text: home.city);
    _region = TextEditingController(text: home.region);
    _country = TextEditingController(text: home.country);
    _birthDate = profile?.birthDate;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _city.dispose();
    _region.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: l.profileBirthDate,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final l = AppLocalizations.of(context);
    final ok = await auth.updateProfile(
      firstName: _firstName.text,
      lastName: _lastName.text,
      phoneNumber: _phone.text,
      birthDate: _birthDate,
      homeLocation: GeoArea(
        city: _city.text.trim(),
        region: _region.text.trim(),
        country: _country.text.trim(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.editProfileSaved)));
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(auth.error ?? l.editProfileSaveFailed)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.editProfileTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.registerFirstNameLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator:
                      (v) => l.validateRequired(
                        v,
                        label: l.registerFirstNameRequired,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.registerLastNameLabel,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator:
                      (v) => l.validateRequired(
                        v,
                        label: l.registerLastNameRequired,
                      ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.registerBirthDateLabel,
                      prefixIcon: const Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _birthDate == null
                          ? l.actionSelect
                          : formatDate(_birthDate!),
                      style: TextStyle(
                        color: _birthDate == null ? AppColors.gray : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l.registerPhoneLabel,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  validator: l.validatePhone,
                ),
                const SizedBox(height: 24),
                Text(
                  l.editProfileResidence,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _city,
                  decoration: InputDecoration(
                    labelText: l.editProfileCity,
                    prefixIcon: const Icon(Icons.location_city_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _region,
                  decoration: InputDecoration(
                    labelText: l.editProfileRegion,
                    prefixIcon: const Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _country,
                  decoration: InputDecoration(
                    labelText: l.editProfileCountry,
                    prefixIcon: const Icon(Icons.public_outlined),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: busy ? null : _save,
                  child:
                      busy
                          ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.dark,
                            ),
                          )
                          : Text(l.actionSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
