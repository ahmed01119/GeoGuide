import 'package:geoguide/cubit/places_cubit.dart';
import 'package:geoguide/services/Wikipedia%20service.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:geoguide/services/nearby-service.dart';
import 'package:geoguide/services/pipe_service.dart';
import 'package:geoguide/services/places_service.dart';
import 'package:geoguide/services/planner_ai_service.dart';
import 'package:geoguide/services/search-service.dart';
import 'package:geoguide/services/place_repository.dart';

class AppInjector {
  AppInjector._();

  static final FirebaseService firebase = FirebaseService();
  static final WikipediaService wikipedia = WikipediaService();
  static final ImageService images = ImageService();
  static final NearbyService nearby = NearbyService();

  static final GooglePlacesService googlePlaces = GooglePlacesService(
    imageService: images,
  );

  static final PlaceRepository repository = PlaceRepository(
    firebase: firebase,
    images: images,
    wikipedia: wikipedia,
    nearby: nearby,
  );

  static final SearchEngine search = SearchEngine(
    firebase: firebase,
    wikipedia: wikipedia,
  );

  static final PlannerService planner = PlannerService();

  static final DataPipelineService pipeline = DataPipelineService(
    googlePlaces: googlePlaces,
    images: images,
    wikipedia: wikipedia,
    firebase: firebase,
    nearby: nearby,
  );

  static PlacesCubit buildPlacesCubit() {
    return PlacesCubit(
      firebase: firebase,
      pipeline: pipeline,
    );
  }
}
