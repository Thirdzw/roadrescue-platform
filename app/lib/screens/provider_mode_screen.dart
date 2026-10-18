import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/common_widgets.dart';
import '../widgets/provider_rescue_jobs_panel.dart';

enum _ReviewStatus { submitted, underReview, approved, rejected, resubmission }

class ProviderModeScreen extends StatefulWidget {
  final VoidCallback onSwitchToMotorist;
  final bool isDemo;

  const ProviderModeScreen({
    super.key,
    required this.onSwitchToMotorist,
    this.isDemo = false,
  });

  @override
  State<ProviderModeScreen> createState() => _ProviderModeScreenState();
}

class _ProviderModeScreenState extends State<ProviderModeScreen> {
  static const _services = [
    'Mobile mechanic',
    'Workshop mechanic',
    'Tow operator',
  ];
  static const _addons = [
    'Battery jump-start',
    'Tyre change',
    'Fuel delivery',
  ];

  final _legalName = TextEditingController();
  final _workshopName = TextEditingController();
  final _address = TextEditingController();
  final _specialities = TextEditingController();
  final _equipment = TextEditingController();
  final _experience = TextEditingController();
  final _truckMake = TextEditingController();
  final _truckModel = TextEditingController();
  final _truckYear = TextEditingController();
  final _truckColour = TextEditingController();
  final _plate = TextEditingController();
  final _capacity = TextEditingController();
  final _ecoCash = TextEditingController();
  final _diagnosis = TextEditingController();
  final _quote = TextEditingController(text: '25.00');
  final _imagePicker = ImagePicker();

  final Set<String> _selectedAddons = {};
  final Map<String, XFile> _attachedDocuments = {};
  String _service = _services.first;
  String _gender = 'Prefer not to say';
  DateTime? _dateOfBirth;
  bool _acceptedRules = false;
  bool _started = false;
  bool _providerWorkMode = false;
  int _registrationStep = 0;
  _ReviewStatus? _reviewStatus;
  String? _reviewReason;
  bool _online = false;
  int _jobStage = 0;
  int _secondsLeft = 30;
  int _completedJobs = 0;
  int _ratingForMotorist = 5;
  int _ratingFromMotorist = 5;
  double _earnings = 0;
  String? _lastOfferMessage;
  Timer? _offerTimer;

  bool get _isTowOperator => _service == 'Tow operator';
  bool get _isMechanic => !_isTowOperator;

  @override
  void initState() {
    super.initState();
    if (widget.isDemo) {
      _providerWorkMode = true;
      _online = true;
    }
  }

  List<String> get _requiredDocuments => [
        'National ID photo',
        'Selfie photo',
        if (_isTowOperator || _service == 'Mobile mechanic') "Driver's licence",
        if (_isTowOperator) 'Vehicle registration book',
        if (_isMechanic) 'Trade certificate or experience proof',
        if (_isTowOperator)
          'Tow truck photo'
        else
          'Workshop or service vehicle photo',
      ];

  int get _age {
    final date = _dateOfBirth;
    if (date == null) return 0;
    final now = DateTime.now();
    return now.year -
        date.year -
        ((now.month < date.month ||
                (now.month == date.month && now.day < date.day))
            ? 1
            : 0);
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    _legalName.dispose();
    _workshopName.dispose();
    _address.dispose();
    _specialities.dispose();
    _equipment.dispose();
    _experience.dispose();
    _truckMake.dispose();
    _truckModel.dispose();
    _truckYear.dispose();
    _truckColour.dispose();
    _plate.dispose();
    _capacity.dispose();
    _ecoCash.dispose();
    _diagnosis.dispose();
    _quote.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _nextStep() {
    if (!_validateStep()) return;
    if (_registrationStep < 3) {
      setState(() => _registrationStep++);
      return;
    }
    setState(() {
      _reviewStatus = _ReviewStatus.submitted;
      _reviewReason = null;
      _started = false;
    });
  }

  bool _validateStep() {
    String? message;
    if (_registrationStep == 1) {
      if (_legalName.text.trim().isEmpty) {
        message = 'Enter your legal name to continue.';
      } else if (_dateOfBirth == null) {
        message = 'Add your date of birth to continue.';
      } else if (_age < 18) {
        message = 'Provider applicants must be at least 18.';
      }
    } else if (_registrationStep == 2) {
      if (_isTowOperator &&
          [_truckMake, _truckModel, _truckYear, _truckColour, _plate, _capacity]
              .any((field) => field.text.trim().isEmpty)) {
        message = 'Complete all required tow vehicle details.';
      } else if (_isMechanic &&
          [_workshopName, _address, _specialities, _equipment, _experience]
              .any((field) => field.text.trim().isEmpty)) {
        message = 'Complete all mechanic and business details.';
      }
    } else if (_registrationStep == 3) {
      final missing = _requiredDocuments
          .where((document) => !_attachedDocuments.containsKey(document));
      if (missing.isNotEmpty) {
        message = 'Attach all required document photos to continue.';
      } else if (_ecoCash.text.trim().isEmpty) {
        message = 'Enter an EcoCash number for payouts.';
      } else if (!_acceptedRules) {
        message = 'Accept the pricing and conduct rules to submit.';
      }
    }
    if (message != null) {
      _showMessage(message);
      return false;
    }
    return true;
  }

  void _changeReviewStatus(_ReviewStatus status) {
    setState(() {
      _reviewStatus = status;
      _providerWorkMode = false;
      _reviewReason = switch (status) {
        _ReviewStatus.rejected => 'Licence photo is unclear.',
        _ReviewStatus.resubmission => 'Please upload a clearer ID photo.',
        _ => null,
      };
    });
  }

  void _startOffer() {
    _offerTimer?.cancel();
    setState(() {
      _jobStage = 1;
      _secondsLeft = 30;
      _lastOfferMessage = null;
    });
    _offerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _jobStage != 1) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        _declineOffer(timedOut: true);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _declineOffer({bool timedOut = false}) {
    _offerTimer?.cancel();
    setState(() {
      _jobStage = 0;
      _lastOfferMessage = timedOut
          ? 'Offer expired and was passed to the next-nearest provider.'
          : 'Offer declined and passed to the next-nearest provider.';
    });
  }

  void _acceptOffer() {
    _offerTimer?.cancel();
    setState(() => _jobStage = 2);
  }

  void _simulatePayment() {
    final amount = double.tryParse(_quote.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid quote amount first.');
      return;
    }
    setState(() {
      _earnings += amount;
      _jobStage = 5;
    });
  }

  void _finishJob() {
    setState(() {
      _completedJobs++;
      _jobStage = 0;
      _diagnosis.clear();
      _quote.text = '25.00';
      _online = false;
    });
    _showMessage(_ratingFromMotorist < 3
        ? 'Low customer rating flagged for review.'
        : 'Job complete. You are now offline.');
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (date != null) setState(() => _dateOfBirth = date);
  }

  @override
  Widget build(BuildContext context) {
    if (_providerWorkMode) return _buildProviderDashboard();
    if (_reviewStatus != null) return _buildReviewStatus();
    if (_started) return _buildRegistration();
    return _buildIntroduction();
  }

  Widget _buildIntroduction() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Switch to motorist',
          onPressed: widget.onSwitchToMotorist,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Provider registration'),
        backgroundColor: C.bg,
        actions: [
          if (widget.isDemo)
            TextButton(
              onPressed: _returnToDemoWorkspace,
              child: const Text('Workspace'),
            ),
        ],
      ),
      body: page(const Color(0xFFE8ECF9), [
        heading('Join the verified network',
            'Apply to receive RoadRescue requests.'),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('A clear, reviewed application',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: C.dark)),
          const SizedBox(height: 8),
          const Text(
              'Choose your service, add your details and attach sample document photos. This prototype keeps everything on this device; review and payments are simulated.',
              style: TextStyle(height: 1.45, color: Colors.black54)),
          const SizedBox(height: 16),
          _feature(Icons.verified_user_outlined, 'Manual application review'),
          _feature(Icons.payments_outlined, 'EcoCash payout profile'),
          _feature(Icons.route_outlined, 'Online status and request workflow'),
        ])),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() => _started = true),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Start registration'),
            style: FilledButton.styleFrom(
                backgroundColor: C.navy,
                padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _providerWorkMode = true),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open live provider workspace'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Live job access is restricted by Firebase to verified provider accounts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
        const SizedBox(height: 110),
      ]),
    );
  }

  Widget _feature(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(icon, color: C.green, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: C.dark))),
        ]),
      );

  Widget _buildRegistration() {
    const titles = ['Service', 'Personal', 'Business / vehicle', 'Documents'];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Switch to motorist',
          onPressed: widget.onSwitchToMotorist,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Provider registration'),
        backgroundColor: C.bg,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Step ${_registrationStep + 1} of 4  ·  ${titles[_registrationStep]}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: C.dark)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_registrationStep + 1) / 4,
              color: C.green,
              backgroundColor: C.navy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _registrationContents(),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Row(children: [
          if (_registrationStep > 0)
            OutlinedButton(
              onPressed: () => setState(() => _registrationStep--),
              child: const Text('Back'),
            ),
          const Spacer(),
          FilledButton(
            onPressed: _nextStep,
            style: FilledButton.styleFrom(backgroundColor: C.navy),
            child: Text(
                _registrationStep == 3 ? 'Submit application' : 'Continue'),
          ),
        ]),
      ),
    );
  }

  Widget _registrationContents() {
    switch (_registrationStep) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('What service do you provide?',
              'Choose your main provider category.'),
          RadioGroup<String>(
            groupValue: _service,
            onChanged: (value) {
              if (value != null) setState(() => _service = value);
            },
            child: Column(children: [
              for (final service in _services)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: service,
                  activeColor: C.navy,
                  title: Text(service),
                  secondary: Icon(_serviceIcon(service), color: C.navy),
                ),
            ]),
          ),
          sectionTitle('Optional add-ons'),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              for (final addon in _addons)
                FilterChip(
                  label: Text(addon),
                  selected: _selectedAddons.contains(addon),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedAddons.add(addon);
                    } else {
                      _selectedAddons.remove(addon);
                    }
                  }),
                ),
            ],
          ),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Personal information', 'Applicants must be at least 18.'),
          _input(_legalName, 'Legal name'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(
                labelText: 'Gender', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: 'Prefer not to say', child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _gender = value!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDateOfBirth,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(_dateOfBirth == null
                ? 'Select date of birth'
                : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}  ·  $_age years'),
          ),
          const SizedBox(height: 12),
          _documentTile('Selfie photo',
              subtitle: 'Required for identity review.'),
        ]);
      case 2:
        return _isTowOperator ? _towDetails() : _mechanicDetails();
      default:
        return _documentsAndPayout();
    }
  }

  Widget _mechanicDetails() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('Business details', 'Tell motorists what you can repair.'),
          _input(_workshopName, 'Workshop or trading name'),
          const SizedBox(height: 12),
          _input(_address, 'Workshop address or service area',
              hint: 'Prototype map pin: enter a nearby landmark'),
          const SizedBox(height: 12),
          _input(_specialities, 'Specialities',
              hint: 'Engine, tyres, electrical'),
          const SizedBox(height: 12),
          _input(_equipment, 'Tools or equipment available'),
          const SizedBox(height: 12),
          _input(_experience, 'Years of experience',
              keyboardType: TextInputType.number),
        ],
      );

  Widget _towDetails() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
              'Tow vehicle details', 'Vehicle age limits are configurable.'),
          _input(_truckMake, 'Truck make'),
          const SizedBox(height: 12),
          _input(_truckModel, 'Truck model'),
          const SizedBox(height: 12),
          _input(_truckYear, 'Year', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _input(_truckColour, 'Colour'),
          const SizedBox(height: 12),
          _input(_plate, 'Plate number'),
          const SizedBox(height: 12),
          _input(_capacity, 'Towing capacity', hint: 'For example, 3.5 tonnes'),
        ],
      );

  Widget _documentsAndPayout() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('Document photos',
              'Take a photo or choose an image for each document.'),
          for (final document in _requiredDocuments) _documentTile(document),
          sectionTitle('Optional supporting documents'),
          for (final document in const [
            'Insurance',
            'Reference contact',
            'Police clearance',
          ])
            _documentTile(document, required: false),
          sectionTitle('Payout details'),
          _input(_ecoCash, 'EcoCash number', keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acceptedRules,
            activeColor: C.navy,
            onChanged: (value) =>
                setState(() => _acceptedRules = value ?? false),
            title:
                const Text('I accept the platform pricing and conduct rules.'),
            subtitle: const Text('Simulation only; no payout will be sent.'),
          ),
        ],
      );

  Widget _documentTile(String document,
      {bool required = true, String? subtitle}) {
    final file = _attachedDocuments[document];
    final attached = file != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          attached ? Icons.check_circle_rounded : Icons.add_a_photo_outlined,
          color: attached ? C.green : C.navy,
        ),
        title: Text(document),
        subtitle: Text(subtitle ??
            (attached ? file.name : (required ? 'Required' : 'Optional'))),
        trailing: TextButton(
          onPressed: attached
              ? () => setState(() => _attachedDocuments.remove(document))
              : () => _pickDocument(document),
          child: Text(attached ? 'Remove' : 'Attach'),
        ),
      ),
    );
  }

  Future<void> _pickDocument(String document) async {
    if (widget.isDemo) {
      setState(() {
        _attachedDocuments[document] =
            XFile('demo_${document.replaceAll(' ', '_')}.jpg');
      });
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;

    if (source == ImageSource.camera) {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        _showImagePermissionError(
          'Camera access is needed to take a document photo.',
          openSettings:
              permission.isPermanentlyDenied || permission.isRestricted,
        );
        return;
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final permission = await Permission.photos.request();
      if (!permission.isGranted && !permission.isLimited) {
        _showImagePermissionError(
          'Allow photo access to choose a document image.',
          openSettings:
              permission.isPermanentlyDenied || permission.isRestricted,
        );
        return;
      }
    }

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (image == null || !mounted) return;
      setState(() => _attachedDocuments[document] = image);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open the selected image source.')),
      );
    }
  }

  void _showImagePermissionError(String message, {required bool openSettings}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: openSettings
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              )
            : null,
      ),
    );
  }

  Widget _input(TextEditingController controller, String label,
          {String? hint, TextInputType? keyboardType}) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _buildReviewStatus() {
    final status = _reviewStatus!;
    final approved = status == _ReviewStatus.approved;
    final retry = status == _ReviewStatus.rejected ||
        status == _ReviewStatus.resubmission;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Switch to motorist',
          onPressed: widget.onSwitchToMotorist,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Application status'),
        backgroundColor: C.bg,
        actions: [
          if (widget.isDemo)
            TextButton(
              onPressed: _returnToDemoWorkspace,
              child: const Text('Workspace'),
            ),
        ],
      ),
      body: page(const Color(0xFFE8ECF9), [
        heading('Provider application', 'Review progress for this prototype.'),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: approved
                  ? C.green.withValues(alpha: 0.14)
                  : C.navy.withValues(alpha: 0.12),
              child: Icon(
                  approved
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                  color: approved ? C.green : C.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_statusLabel(status),
                        style: const TextStyle(
                            color: C.dark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text(_statusDescription(status),
                        style: const TextStyle(color: Colors.black54)),
                  ]),
            ),
          ]),
          const SizedBox(height: 22),
          _timeline(status),
          if (_reviewReason != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF2E3),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Reviewer note: $_reviewReason'),
            ),
          ],
        ])),
        if (approved) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _providerWorkMode = true),
              icon: const Icon(Icons.toggle_on_rounded),
              label: const Text('Enter provider mode'),
              style: FilledButton.styleFrom(backgroundColor: C.green),
            ),
          ),
        ],
        if (retry)
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _started = true;
              _registrationStep = 3;
              _reviewStatus = null;
            }),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Update application'),
          ),
        const SizedBox(height: 20),
        sectionTitle('Prototype review controls'),
        const Text(
            'These controls simulate a manual reviewer. Status is held in memory and is not sent to Firebase.',
            style: TextStyle(color: Colors.black54, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final item in _ReviewStatus.values)
            ChoiceChip(
              label: Text(_statusLabel(item)),
              selected: status == item,
              onSelected: (_) => _changeReviewStatus(item),
            ),
        ]),
        const SizedBox(height: 110),
      ]),
    );
  }

  Widget _timeline(_ReviewStatus status) {
    final decision = switch (status) {
      _ReviewStatus.approved => 'Approved',
      _ReviewStatus.rejected => 'Rejected',
      _ReviewStatus.resubmission => 'Needs resubmission',
      _ => 'Awaiting decision',
    };
    return Column(children: [
      _timelineItem('Submitted', true, Icons.check_rounded),
      _timelineItem('Under review', status != _ReviewStatus.submitted,
          Icons.search_rounded),
      _timelineItem(
          decision,
          status == _ReviewStatus.approved ||
              status == _ReviewStatus.rejected ||
              status == _ReviewStatus.resubmission,
          status == _ReviewStatus.approved
              ? Icons.verified_rounded
              : Icons.flag_outlined,
          last: true),
    ]);
  }

  Widget _timelineItem(String label, bool complete, IconData icon,
          {bool last = false}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  complete ? C.green : C.navy.withValues(alpha: 0.12),
              child:
                  Icon(icon, size: 16, color: complete ? Colors.white : C.navy),
            ),
            if (!last)
              Container(
                  height: 24,
                  width: 2,
                  color: complete ? C.green : C.navy.withValues(alpha: 0.15)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 4),
          child: Text(label,
              style: TextStyle(
                  fontWeight: complete ? FontWeight.w700 : FontWeight.normal,
                  color: complete ? C.dark : Colors.black45)),
        ),
      ]);

  String _statusLabel(_ReviewStatus status) => switch (status) {
        _ReviewStatus.submitted => 'Submitted',
        _ReviewStatus.underReview => 'Under review',
        _ReviewStatus.approved => 'Approved',
        _ReviewStatus.rejected => 'Rejected',
        _ReviewStatus.resubmission => 'Needs resubmission',
      };

  String _statusDescription(_ReviewStatus status) => switch (status) {
        _ReviewStatus.submitted => 'Your application is in the review queue.',
        _ReviewStatus.underReview => 'A reviewer is checking your documents.',
        _ReviewStatus.approved => 'You can now simulate accepting rescue jobs.',
        _ReviewStatus.rejected => 'This application was not approved.',
        _ReviewStatus.resubmission =>
          'Update the requested documents and resubmit.',
      };

  Widget _buildProviderDashboard() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Switch to motorist',
          onPressed: widget.onSwitchToMotorist,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Provider mode'),
        backgroundColor: C.bg,
        actions: [
          TextButton(
            onPressed: widget.onSwitchToMotorist,
            child: const Text('Motorist'),
          ),
        ],
      ),
      body: page(const Color(0xFFE8F5EB), [
        heading(
          'Your workday',
          'Live client tracking is available for accepted, opted-in rescue jobs.',
        ),
        const ProviderRescueJobsPanel(),
        const SizedBox(height: 16),
        sectionTitle('Demo provider workflow'),
        card(Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_online ? 'You are online' : 'You are offline',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: C.dark)),
              Text(
                  _online
                      ? 'Demo GPS sharing is active'
                      : 'Not visible to motorists',
                  style: const TextStyle(color: Colors.black54)),
            ]),
          ),
          Switch.adaptive(
            value: _online,
            activeTrackColor: C.green,
            onChanged: (online) {
              if (!online && _jobStage == 1) {
                _offerTimer?.cancel();
                setState(() {
                  _online = false;
                  _jobStage = 0;
                  _lastOfferMessage =
                      'Offer declined and passed to the next-nearest provider.';
                });
              } else {
                setState(() => _online = online);
              }
            },
          ),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric('Jobs completed', '$_completedJobs')),
          const SizedBox(width: 10),
          Expanded(
              child: _metric(
                  'Demo earnings', '\$${_earnings.toStringAsFixed(2)}')),
        ]),
        sectionTitle('Incoming rescue request'),
        if (!_online)
          card(const Text('Go online to receive a simulated SOS request.'))
        else
          _jobCard(),
        if (widget.isDemo) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _providerWorkMode = false;
              _started = true;
              _reviewStatus = null;
              _registrationStep = 0;
            }),
            icon: const Icon(Icons.assignment_outlined),
            label: const Text('Try provider registration simulation'),
          ),
        ],
        const SizedBox(height: 110),
      ]),
    );
  }

  void _returnToDemoWorkspace() {
    setState(() {
      _providerWorkMode = true;
      _started = false;
      _reviewStatus = null;
    });
  }

  Widget _metric(String label, String value) => card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: C.dark, fontSize: 21, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      ));

  Widget _jobCard() {
    if (_jobStage == 0) {
      return card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.radar_rounded, color: C.green),
          SizedBox(width: 8),
          Expanded(
            child: Text('Waiting for a nearby request',
                style: TextStyle(fontWeight: FontWeight.w700, color: C.dark)),
          ),
        ]),
        if (_lastOfferMessage != null) ...[
          const SizedBox(height: 10),
          Text(_lastOfferMessage!,
              style: const TextStyle(color: Colors.black54)),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _startOffer,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Simulate incoming SOS'),
        ),
      ]));
    }

    if (_jobStage == 1) {
      return card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Vehicle breakdown nearby',
                style: TextStyle(fontWeight: FontWeight.w800, color: C.dark)),
          ),
          Text('00:${_secondsLeft.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  color: C.sosDark, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        _requestDetail(Icons.near_me_rounded, '2.4 km away'),
        _requestDetail(Icons.car_repair_rounded, 'Flat tyre · Sedan'),
        _requestDetail(Icons.location_on_outlined, 'Samora Machel Avenue'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _declineOffer,
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _acceptOffer,
              style: FilledButton.styleFrom(backgroundColor: C.green),
              child: const Text('Accept'),
            ),
          ),
        ]),
      ]));
    }

    if (_jobStage == 2) {
      return card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Request accepted',
            style: TextStyle(fontWeight: FontWeight.w800, color: C.dark)),
        const SizedBox(height: 8),
        const Text('Navigation is simulated for this prototype.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => setState(() => _jobStage = 3),
          icon: const Icon(Icons.location_on_rounded),
          label: const Text('Mark arrived'),
          style: FilledButton.styleFrom(backgroundColor: C.navy),
        ),
      ]));
    }

    if (_jobStage == 3) {
      return card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Diagnose and quote',
            style: TextStyle(fontWeight: FontWeight.w800, color: C.dark)),
        const SizedBox(height: 12),
        _input(_diagnosis, 'Diagnosis', hint: 'Describe the repair needed'),
        const SizedBox(height: 12),
        _input(_quote, 'Upfront quote (USD)',
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => setState(() => _jobStage = 4),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send quote to motorist'),
          style: FilledButton.styleFrom(backgroundColor: C.navy),
        ),
      ]));
    }

    if (_jobStage == 4) {
      return card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quote sent · Awaiting EcoCash',
            style: TextStyle(fontWeight: FontWeight.w800, color: C.dark)),
        const SizedBox(height: 8),
        Text(
            'Diagnosis: ${_diagnosis.text.isEmpty ? 'Tyre repair' : _diagnosis.text}'),
        Text('Upfront amount: \$${_quote.text}'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _simulatePayment,
          icon: const Icon(Icons.payments_rounded),
          label: const Text('Simulate EcoCash payment'),
          style: FilledButton.styleFrom(backgroundColor: C.green),
        ),
      ]));
    }

    return card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payment received · Rate the job',
          style: TextStyle(fontWeight: FontWeight.w800, color: C.dark)),
      const SizedBox(height: 6),
      Text('Demo earnings: \$${_quote.text}'),
      const SizedBox(height: 12),
      _ratingSelector('Rate the motorist', _ratingForMotorist,
          (rating) => setState(() => _ratingForMotorist = rating)),
      _ratingSelector('Your received rating', _ratingFromMotorist,
          (rating) => setState(() => _ratingFromMotorist = rating)),
      if (_ratingFromMotorist < 3)
        const Text('Low rating will be flagged for a review.',
            style: TextStyle(color: C.sosDark)),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _finishJob,
        style: FilledButton.styleFrom(backgroundColor: C.navy),
        child: const Text('Complete job'),
      ),
    ]));
  }

  Widget _requestDetail(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Icon(icon, size: 18, color: C.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _ratingSelector(
          String label, int rating, ValueChanged<int> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(label)),
          for (var star = 1; star <= 5; star++)
            InkWell(
              onTap: () => onChanged(star),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: const Color(0xFFFFB300),
                  size: 20,
                ),
              ),
            ),
        ]),
      );

  IconData _serviceIcon(String service) => switch (service) {
        'Mobile mechanic' => Icons.build_circle_outlined,
        'Workshop mechanic' => Icons.home_repair_service_outlined,
        _ => Icons.rv_hookup_rounded,
      };
}
