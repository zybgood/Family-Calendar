import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'calendar_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const bgColor = Color(0xFFFFFDF5);
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFFAC638);
  static const secondaryAccent = Color(0xFFF59E0B);
  static const labelColor = Color(0xFF1E293B);
  static const hintColor = Color(0xFF64748B);
  static const placeholderColor = Color(0xFF94A3B8);
  static const borderColor = Color(0xFFE2E8F0);

  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final familyNameController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedAvatar;

  bool _isLoading = false;
  bool _obscurePassword = true;

  final List<String> _familyRoles = [
    'father',
    'mother',
    'son',
    'daughter',
    'grandpa',
    'grandma',
    'other',
  ];

  String? _selectedFamilyRole;

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    familyNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() {
        _selectedAvatar = image;
      });
    } catch (e) {
      _showMessage('Failed to pick image: $e');
    }
  }

  Future<String> _uploadAvatar(String uid) async {
    if (_selectedAvatar == null) return '';

    final file = File(_selectedAvatar!.path);

    final ref = FirebaseStorage.instance
        .ref()
        .child('user_avatars')
        .child('$uid.jpg');

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<void> _register() async {
    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final familyName = familyNameController.text.trim();

    if (_selectedAvatar == null) {
      _showMessage('Please upload your profile photo.');
      return;
    }

    if (fullName.isEmpty) {
      _showMessage('Please enter your full name.');
      return;
    }

    if (email.isEmpty) {
      _showMessage('Please enter your email.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter your password.');
      return;
    }

    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }

    // 如果填写了家庭名，则必须选择家庭角色
    if (familyName.isNotEmpty && _selectedFamilyRole == null) {
      _showMessage('Please select your family role.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'User creation failed. Please try again.',
        );
      }

      await user.updateDisplayName(fullName);

      final uid = user.uid;
      final now = Timestamp.now();

      final photoURL = await _uploadAvatar(uid);
      await user.updatePhotoURL(photoURL);

      final username = _generateUsername(fullName, email);

      final batch = firestore.batch();

      // 1. users/{uid}
      final userDocRef = firestore.collection('users').doc(uid);
      batch.set(userDocRef, {
        'uid': uid,
        'email': email,
        'username': username,
        'fullName': fullName,
        'photoURL': photoURL,
        'bio': '',
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'lastLoginAt': now,
      });

      // 如果填写 familyName，则创建家庭
      if (familyName.isNotEmpty) {
        final familyDocRef = firestore.collection('families').doc();
        final familyId = familyDocRef.id;

        // 2. families/{familyId}
        batch.set(familyDocRef, {
          'familyId': familyId,
          'familyName': familyName,
          'description': 'Our family group',
          'createdBy': uid,
          'createdAt': now,
          'updatedAt': now,
          'photoURL': '',
          'isArchived': false,
        });

        // 3. families/{familyId}/members/{uid}
        final familyMemberRef = firestore
            .collection('families')
            .doc(familyId)
            .collection('members')
            .doc(uid);

        batch.set(familyMemberRef, {
          'uid': uid,
          'nickname': fullName,
          'role': 'owner', // 系统权限角色
          'familyRole': _selectedFamilyRole, // 家庭身份角色
          'status': 'active',
          'joinedAt': now,
        });

        // 4. users/{uid}/families/{familyId}
        final userFamilyRef = firestore
            .collection('users')
            .doc(uid)
            .collection('families')
            .doc(familyId);

        batch.set(userFamilyRef, {
          'familyId': familyId,
          'familyName': familyName,
          'role': 'owner',
          'familyRole': _selectedFamilyRole,
          'joinedAt': now,
          'photoURL': '',
        });
      }

      await batch.commit();

      if (!mounted) return;

      _showMessage('Registration successful.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const CalendarScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_getFirebaseAuthErrorMessage(e));
    } catch (e) {
      _showMessage('Registration failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _generateUsername(String fullName, String email) {
    final trimmedName = fullName.trim();
    if (trimmedName.isNotEmpty) {
      return trimmedName.replaceAll(' ', '');
    }
    return email.split('@').first;
  }

  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'weak-password':
        return 'The password is too weak.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Registration failed. Please try again.';
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _familyRoleLabel(String role) {
    switch (role) {
      case 'father':
        return 'Father';
      case 'mother':
        return 'Mother';
      case 'son':
        return 'Son';
      case 'daughter':
        return 'Daughter';
      case 'grandpa':
        return 'Grandpa';
      case 'grandma':
        return 'Grandma';
      case 'other':
        return 'Other';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildLogoHeader(),
                    const SizedBox(height: 24),
                    _buildRegisterCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.2),
            border: Border.all(
              color: accentColor.withOpacity(0.1),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Center(
            child: Icon(
              Icons.location_on,
              size: 40,
              color: accentColor,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Cottage',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: primaryColor,
            letterSpacing: -0.75,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your family\'s shared space',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF7E7664),
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 25,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAvatarPicker(),
            const SizedBox(height: 20),
            _buildFullNameField(),
            const SizedBox(height: 20),
            _buildEmailField(),
            const SizedBox(height: 20),
            _buildPasswordField(),
            const SizedBox(height: 20),
            _buildFamilyNameField(),
            const SizedBox(height: 20),
            _buildFamilyRoleField(),
            const SizedBox(height: 28),
            _buildCreateAccountButton(),
            const SizedBox(height: 32),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _isLoading ? null : _pickAvatar,
          child: CircleAvatar(
            radius: 42,
            backgroundColor: accentColor.withOpacity(0.2),
            backgroundImage: _selectedAvatar != null
                ? FileImage(File(_selectedAvatar!.path))
                : null,
            child: _selectedAvatar == null
                ? const Icon(
              Icons.person,
              size: 40,
              color: primaryColor,
            )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _isLoading ? null : _pickAvatar,
          child: const Text(
            'Upload Profile Photo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: secondaryAccent,
              fontFamily: 'Plus Jakarta Sans',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Full Name',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
            child: TextField(
              controller: fullNameController,
              decoration: const InputDecoration(
                hintText: 'Enter your full name',
                hintStyle: TextStyle(
                  color: placeholderColor,
                  fontSize: 16,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 16,
                color: primaryColor,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email Address',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'name@example.com',
                hintStyle: TextStyle(
                  color: placeholderColor,
                  fontSize: 16,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 16,
                color: primaryColor,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 6),
            child: TextField(
              controller: passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: 'Create a secure password',
                hintStyle: const TextStyle(
                  color: placeholderColor,
                  fontSize: 16,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                border: InputBorder.none,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: hintColor,
                  ),
                ),
              ),
              style: const TextStyle(
                fontSize: 16,
                color: primaryColor,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Family Name (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
            child: TextField(
              controller: familyNameController,
              onChanged: (_) {
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'Enter your family name (optional)',
                hintStyle: TextStyle(
                  color: placeholderColor,
                  fontSize: 16,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 16,
                color: primaryColor,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyRoleField() {
    final hasFamilyName = familyNameController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasFamilyName ? 'Family Role *' : 'Family Role',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: hasFamilyName ? Colors.white : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 4),
            child: DropdownButtonFormField<String>(
              value: _selectedFamilyRole,
              isExpanded: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
              hint: Text(
                hasFamilyName
                    ? 'Select your role in the family'
                    : 'Fill family name first',
                style: const TextStyle(
                  color: placeholderColor,
                  fontSize: 16,
                  fontFamily: 'Plus Jakarta Sans',
                ),
              ),
              items: _familyRoles.map((role) {
                return DropdownMenuItem<String>(
                  value: role,
                  child: Text(
                    _familyRoleLabel(role),
                    style: const TextStyle(
                      fontSize: 16,
                      color: primaryColor,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                  ),
                );
              }).toList(),
              onChanged: hasFamilyName && !_isLoading
                  ? (value) {
                setState(() {
                  _selectedFamilyRole = value;
                });
              }
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateAccountButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [accentColor, secondaryAccent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _register,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _isLoading
                ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
                : const Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: hintColor,
            fontFamily: 'Plus Jakarta Sans',
          ),
          children: [
            const TextSpan(text: 'Already have an account? '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Sign In',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: secondaryAccent,
                    fontFamily: 'Plus Jakarta Sans',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}