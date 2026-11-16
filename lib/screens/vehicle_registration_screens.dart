// screens/vehicle_registration_screens.dart
//
// "Earn with Us" भित्र Ride Driver छान्दा Bike/Car/Auto-Rickshaw का लागि
// छुट्टाछुट्टै, dedicated entry point दिने तीन thin screen। तीनैले
// `DriverRegistrationFlow` कै engine (license/vehicle-docs/identity/review
// steps, Firestore लेखाइ, Storage upload) प्रयोग गर्छन् — केवल
// `fixedVehicleType` तोकिदिएर Vehicle Category step हटाउने र त्यही
// vehicle-अनुसारको label/field (Bluebook Number, Plate No, Seating
// Capacity + AC, Route Permit) देखाउने।
import '../driver_registration_flow.dart';

class BikeRegistrationScreen extends DriverRegistrationFlow {
  const BikeRegistrationScreen({super.key})
      : super(fixedVehicleType: 'Bike');
}

class CarRegistrationScreen extends DriverRegistrationFlow {
  const CarRegistrationScreen({super.key}) : super(fixedVehicleType: 'Car');
}

class AutoRickshawRegistrationScreen extends DriverRegistrationFlow {
  const AutoRickshawRegistrationScreen({super.key})
      : super(fixedVehicleType: 'Auto');
}
