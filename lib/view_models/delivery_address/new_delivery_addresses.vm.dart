import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:fuodz/models/address.dart';
import 'package:fuodz/models/delivery_address.dart';
import 'package:fuodz/requests/delivery_address.request.dart';
import 'package:fuodz/services/alert.service.dart';
import 'package:fuodz/view_models/delivery_address/base_delivery_addresses.vm.dart';
import 'package:localize_and_translate/localize_and_translate.dart';
import 'package:fuodz/extensions/context.dart';
import 'package:map_location_picker/map_location_picker.dart';
import 'package:fuodz/constants/app_strings.dart';

class NewDeliveryAddressesViewModel extends BaseDeliveryAddressesViewModel {
  //
  DeliveryAddressRequest deliveryAddressRequest = DeliveryAddressRequest();
  TextEditingController nameTEC = TextEditingController();
  TextEditingController addressTEC = TextEditingController();
  TextEditingController descriptionTEC = TextEditingController();
  TextEditingController what3wordsTEC = TextEditingController();
  bool isDefault = false;
  DeliveryAddress? deliveryAddress = new DeliveryAddress();

  //
  NewDeliveryAddressesViewModel(BuildContext context) {
    this.viewContext = context;
  }

  //
  showAddressLocationPicker() async {
    dynamic result = await newPlacePicker();

    if (result is GeocodingResult) {
      GeocodingResult locationResult = result;
      addressTEC.text = locationResult.formattedAddress ?? "";
      deliveryAddress!.address = locationResult.formattedAddress;
      deliveryAddress!.latitude = locationResult.geometry.location.lat;
      deliveryAddress!.longitude = locationResult.geometry.location.lng;

      if (locationResult.addressComponents.isNotEmpty) {
        //fetch city, state and country from address components
        locationResult.addressComponents.forEach((addressComponent) {
          if (addressComponent.types.contains("locality")) {
            deliveryAddress!.city = addressComponent.longName;
          }
          if (addressComponent.types.contains("administrative_area_level_1")) {
            deliveryAddress!.state = addressComponent.longName;
          }
          if (addressComponent.types.contains("country")) {
            deliveryAddress!.country = addressComponent.longName;
          }
        });
      } else {
        // From coordinates
        setBusy(true);
        deliveryAddress = await getLocationCityName(deliveryAddress!);
        setBusy(false);
      }
      notifyListeners();
    } else if (result is Address) {
      Address locationResult = result;
      addressTEC.text = locationResult.addressLine ?? "";
      deliveryAddress!.address = locationResult.addressLine;
      deliveryAddress!.latitude = locationResult.coordinates?.latitude;
      deliveryAddress!.longitude = locationResult.coordinates?.longitude;
      deliveryAddress!.city = locationResult.locality;
      deliveryAddress!.state = locationResult.adminArea;
      deliveryAddress!.country = locationResult.countryName;
    }
  }

  //

  void toggleDefault(bool? value) {
    isDefault = value ?? false;
    deliveryAddress!.isDefault = isDefault ? 1 : 0;
    notifyListeners();
  }

  // realiza reverse geocode via Google e retorna map com city/state/country (ou null)
  Future<Map<String, String>?> reverseGeocode(double lat, double lng) async {
    final apiKey = AppStrings.googleMapApiKey;
    if (apiKey == null || apiKey.isEmpty) return null;
    final url =
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey";
    try {
      final res = await http.get(Uri.parse(url)).timeout(Duration(seconds: 8));
      final body = json.decode(res.body);
      if (body is Map && body['status'] == 'OK' && body['results'] is List && body['results'].isNotEmpty) {
        final components = body['results'][0]['address_components'] as List<dynamic>;
        String? city, state, country;
        for (var c in components) {
          final types = List<String>.from(c['types'] ?? []);
          if (types.contains('locality') || types.contains('sublocality') || types.contains('administrative_area_level_2')) {
            city ??= c['long_name'];
          }
          if (types.contains('administrative_area_level_1')) {
            state ??= c['long_name'];
          }
          if (types.contains('country')) {
            country ??= c['long_name'];
          }
        }
        return {
          'city': city ?? '',
          'state': state ?? '',
          'country': country ?? '',
        };
      }
    } catch (e) {
      print("DEBUG: reverseGeocode error -> $e");
    }
    return null;
  }

  // Exemplo: antes de salvar, tente preencher cidade/estado/país no model
  Future<void> saveNewDeliveryAddress() async {
    if (formKey.currentState == null || !formKey.currentState!.validate()) return;

    deliveryAddress!.name = nameTEC.text;
    deliveryAddress!.description = descriptionTEC.text;

    // Se latitude/longitude presentes e city/state/country vazios, tenta obter via Google
    if ((deliveryAddress!.city == null || deliveryAddress!.city!.isEmpty) &&
        (deliveryAddress!.state == null || deliveryAddress!.state!.isEmpty) &&
        (deliveryAddress!.country == null || deliveryAddress!.country!.isEmpty) &&
        deliveryAddress!.latitude != null &&
        deliveryAddress!.longitude != null) {
      final geo = await reverseGeocode(
        deliveryAddress!.latitude!,
        deliveryAddress!.longitude!,
      );
      if (geo != null) {
        deliveryAddress!.city = geo['city'];
        deliveryAddress!.state = geo['state'];
        deliveryAddress!.country = geo['country'];
        print("DEBUG: reverseGeocode filled -> $geo");
      }
    }

    setBusy(true);
    try {
      final apiRespose = await deliveryAddressRequest.saveDeliveryAddress(deliveryAddress!);

      print("DEBUG: saveDeliveryAddress -> $apiRespose");
      // resto do seu fluxo (AlertService, etc.)
      AlertService.dynamic(
        type: apiRespose.allGood ? AlertType.success : AlertType.error,
        title: apiRespose.allGood ? "Endereço salvo".tr() : "Falha".tr(),
        text: apiRespose.message ?? (apiRespose.errors?.join(", ") ?? ""),
        onConfirm: () {
          if (apiRespose.allGood) viewContext.pop(true);
        },
      );
    } catch (e, st) {
      print("DEBUG: saveNewDeliveryAddress error -> $e\n$st");
      try {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(content: Text("Erro ao salvar endereço. Verifique os logs.")),
        );
      } catch (_) {}
    } finally {
      setBusy(false);
    }
  }

  // remove UI from VM: keep stub so chamadas ainda funcionem
  void showModal() {
    // UI foi movida para a view (address_search.view.dart).
    // Chamadas a vm.showModal() continuam válidas, mas a lógica visual
    // deve estar na view.
  }
} // fim da classe NewDeliveryAddressesViewModel
