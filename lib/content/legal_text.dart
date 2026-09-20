// content/legal_text.dart
//
// Help/Support र Privacy का लामो text यहाँ (bilingual)। यी KaamMitra का आफ्नै
// original copy हुन्; कुनै अन्य app को text यहाँ राखिएको छैन।
import '../l10n/strings.dart';

String _pick(String en, String ne) => S.isNepali ? ne : en;

class LegalText {
  LegalText._();

  /// Service Standard — नेपालको श्रम कानुनका सिद्धान्त + KaamMitra का प्रतिबद्धता।
  static String get serviceStandard => _pick(
        '''KaamMitra follows the principles of Nepal's labour laws (the Labour Act and Labour Rules) and expects every worker and employer on the platform to do the same.

Workers' rights we uphold:
• Fair, agreed pay — the price confirmed in the app must be paid in full and on time after the work is done.
• A safe workplace — employers must not ask a worker to do anything unsafe or beyond the agreed task without consent.
• No forced or child labour — anyone offering or requesting work must be 18 or older.
• Dignity and equal treatment — no discrimination by gender, caste, ethnicity, religion or disability.
• Rest and reasonable hours — jobs are booked for a defined scope; extra time or work must be re-agreed.
• The right to refuse or stop unsafe work without penalty.

Both sides agree to:
• Communicate honestly about the task, price and timing.
• Keep to the confirmed booking, or cancel early with notice.
• Raise any problem through the app's report or support option rather than confrontation.

KaamMitra may suspend or block accounts that break these standards.''',
        '''KaamMitra ले नेपालको श्रम कानुन (श्रम ऐन र श्रम नियमावली) का सिद्धान्त पालना गर्छ र प्लेटफर्ममा भएका हरेक कामदार र रोजगारदातासँग पनि सोही अपेक्षा गर्छ।

हामीले संरक्षण गर्ने कामदारका हक:
• उचित, सहमत ज्याला — app मा पुष्टि भएको मूल्य काम सकिएपछि पूरै र समयमै तिर्नुपर्छ।
• सुरक्षित कार्यस्थल — रोजगारदाताले कामदारलाई सहमति बिना असुरक्षित वा सहमत कामभन्दा बाहिरको काम गर्न लगाउन पाउँदैन।
• जबरजस्ती वा बालश्रम निषेध — काम दिने वा माग्ने जो कोही १८ वर्ष वा माथिको हुनुपर्छ।
• मर्यादा र समान व्यवहार — लिङ्ग, जात, जातीयता, धर्म वा अपाङ्गताका आधारमा भेदभाव हुँदैन।
• विश्राम र उचित समय — काम तोकिएको दायराका लागि बुक हुन्छ; थप समय वा काम पुनः सहमति गर्नुपर्छ।
• असुरक्षित काम बिना दण्ड अस्वीकार गर्ने वा रोक्ने अधिकार।

दुवै पक्ष सहमत हुन्छन्:
• काम, मूल्य र समयबारे इमानदारीपूर्वक कुराकानी गर्ने।
• पुष्टि भएको बुकिङ पालना गर्ने, वा सूचना दिएर अगावै रद्द गर्ने।
• कुनै समस्या भए भिडन्तभन्दा app को report वा support विकल्पबाट उठाउने।

यी मापदण्ड उल्लंघन गर्ने खातालाई KaamMitra ले निलम्बन वा बन्द गर्न सक्छ।''',
      );

  /// FAQ — प्रश्न/उत्तर जोडी। पहिलो: "How to book your service".
  static List<(String, String)> get faq => [
        (
          _pick('How to book your service', 'सेवा कसरी बुक गर्ने'),
          _pick(
            '''1. On the Home screen, search for the service you need or tap a category.
2. Open a worker's profile to see their experience, rate and distance.
3. Tap "Offer your price", enter the amount you want to pay and a short description of the task.
4. Send the offer. The worker can accept it or send back a counter price.
5. When both sides agree, the booking is confirmed — you can then chat with the worker and track it in My Bookings.''',
            '''१. Home screen मा चाहिएको सेवा खोज्नुहोस् वा श्रेणीमा tap गर्नुहोस्।
२. कामदारको profile खोलेर अनुभव, दर र दूरी हेर्नुहोस्।
३. "आफ्नो मूल्य offer गर्नुहोस्" मा tap गरी तपाईंले तिर्न चाहेको रकम र कामको छोटो विवरण लेख्नुहोस्।
४. Offer पठाउनुहोस्। कामदारले स्वीकार गर्न वा नयाँ मूल्य फिर्ता पठाउन सक्छ।
५. दुवै पक्ष सहमत भएपछि बुकिङ पुष्टि हुन्छ — त्यसपछि कामदारसँग chat गर्न र My Bookings मा track गर्न सकिन्छ।''',
          )
        ),
        (
          _pick('How does price bidding work?', 'मूल्य bidding कसरी चल्छ?'),
          _pick(
            'You name the price you want to pay. The worker can accept it or propose a different one. Nothing is charged by the app — you settle the agreed amount directly with the worker after the job.',
            'तपाईंले तिर्न चाहेको मूल्य राख्नुहोस्। कामदारले स्वीकार गर्न वा फरक मूल्य प्रस्ताव गर्न सक्छ। app ले केही शुल्क लिँदैन — काम सकिएपछि सहमत रकम कामदारलाई सिधै तिर्नुहोस्।',
          )
        ),
        (
          _pick('Is my payment held by KaamMitra?',
              'मेरो भुक्तानी KaamMitra ले राख्छ?'),
          _pick(
            'No. Payment happens directly between you and the worker (cash, QR, eSewa or Khalti). KaamMitra only connects you.',
            'होइन। भुक्तानी तपाईं र कामदारबीच सिधै हुन्छ (नगद, QR, eSewa वा Khalti)। KaamMitra ले केवल जोड्ने काम गर्छ।',
          )
        ),
        (
          _pick('What if the worker does not show up?', 'कामदार नआए के गर्ने?'),
          _pick(
            'Use "Worker didn\'t respond" in this Help section, or the Report option, and the admin will follow up. Repeated no-shows lead to the worker being suspended.',
            'यो Help मा भएको "कामदारले जवाफ दिएन" वा Report विकल्प प्रयोग गर्नुहोस्; admin ले हेर्नेछ। पटक-पटक नआउने कामदार निलम्बन हुन्छ।',
          )
        ),
      ];

  /// Privacy Policy — KaamMitra को आफ्नै professional copy।
  static String get privacyPolicy => _pick(
        '''KaamMitra ("we") connects people who need local services with workers who provide them. This policy explains what we collect and why.

What we collect
• Account data: your phone number, name and the role you choose (employer or worker).
• Profile data: for workers, your service type, experience, rate, service area and the certificate you upload.
• Location: your approximate or precise location, used to show nearby workers and distances. You can decline location and still use most of the app.
• Usage data: bookings, offers, chat messages and reports you create in the app.

How we use it
• To run the core service — matching, showing distance, enabling offers and bookings, and delivering chat.
• To keep the platform safe — reviewing reports and acting on accounts that break our Service Standard.
• To contact you about your bookings and account.

What we do not do
• We do not sell your personal data.
• We do not share your contact details with third parties for advertising.
• Workers and employers only see the information needed to complete a booking.

Your choices
• You can edit your profile, change your saved places, or turn off location at any time.
• You can request deletion of your account from Settings; this removes your profile and associated records.

Contact
For any privacy question, use Contact Support in this Help section.''',
        '''KaamMitra ("हामी") ले स्थानीय सेवा चाहिनेहरूलाई सेवा दिने कामदारहरूसँग जोड्छ। यो पोलिसीले हामी के संकलन गर्छौं र किन भन्ने बताउँछ।

हामी के संकलन गर्छौं
• खाता डाटा: तपाईंको फोन नम्बर, नाम र छानिएको भूमिका (रोजगारदाता वा कामदार)।
• प्रोफाइल डाटा: कामदारका लागि — सेवा प्रकार, अनुभव, दर, सेवा क्षेत्र र अपलोड गरिएको प्रमाणपत्र।
• स्थान: नजिकका कामदार र दूरी देखाउन प्रयोग हुने अनुमानित वा सटीक स्थान। तपाईं स्थान नदिई पनि app को धेरैजसो भाग प्रयोग गर्न सक्नुहुन्छ।
• प्रयोग डाटा: app मा तपाईंले बनाएका बुकिङ, offer, chat सन्देश र report।

हामी यसलाई कसरी प्रयोग गर्छौं
• मुख्य सेवा चलाउन — मिलाउने, दूरी देखाउने, offer र बुकिङ, र chat पुर्‍याउने।
• प्लेटफर्म सुरक्षित राख्न — report हेर्ने र Service Standard उल्लंघन गर्ने खातामाथि कारबाही गर्ने।
• तपाईंको बुकिङ र खाताबारे सम्पर्क गर्न।

हामी के गर्दैनौं
• तपाईंको व्यक्तिगत डाटा बेच्दैनौं।
• विज्ञापनका लागि तपाईंको सम्पर्क विवरण तेस्रो पक्षलाई दिँदैनौं।
• कामदार र रोजगारदाताले बुकिङ पूरा गर्न चाहिने जानकारी मात्र देख्छन्।

तपाईंका विकल्प
• तपाईं जुनसुकै बेला profile सम्पादन गर्न, सुरक्षित स्थान बदल्न वा location बन्द गर्न सक्नुहुन्छ।
• Settings बाट खाता delete गर्न अनुरोध गर्न सकिन्छ; यसले तपाईंको profile र सम्बन्धित record हटाउँछ।

सम्पर्क
प्राइभेसी सम्बन्धी कुनै प्रश्नका लागि यो Help को Contact Support प्रयोग गर्नुहोस्।''',
      );

  static String get dataSecurity => _pick(
        '''Your data is secure with us.

• Traffic between the app and our servers is encrypted in transit.
• Account and profile data is stored on Google Firebase, protected by access rules so only you and, where needed for a booking, the other party can read the relevant fields.
• Only an authorised admin can review reports and support messages.
• We keep the minimum data needed to run the service and remove your records when you delete your account.''',
        '''तपाईंको डाटा हामीसँग सुरक्षित छ।

• app र हाम्रा server बीचको traffic encrypt गरिएको हुन्छ।
• खाता र profile डाटा Google Firebase मा राखिन्छ, access rule ले सुरक्षित — सम्बन्धित field तपाईं र बुकिङका लागि चाहिँदा अर्को पक्षले मात्र पढ्न सक्छ।
• अधिकारप्राप्त admin ले मात्र report र support सन्देश हेर्न सक्छ।
• सेवा चलाउन चाहिने न्यूनतम डाटा मात्र राख्छौं र खाता delete गर्दा record हटाउँछौं।''',
      );
}
