import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_icons/flutter_icons.dart';
import 'package:fuodz/constants/app_map_settings.dart';
import 'package:fuodz/constants/app_strings.dart';
import 'package:fuodz/constants/input.styles.dart';
import 'package:fuodz/models/address.dart';
import 'package:fuodz/models/delivery_address.dart';
import 'package:fuodz/utils/ui_spacer.dart';
import 'package:fuodz/widgets/busy_indicator.dart';
import 'package:fuodz/widgets/buttons/custom_button.dart';
import 'package:fuodz/widgets/cards/custom.visibility.dart';
import 'package:fuodz/widgets/filters/ops_autocomplete.dart';
import 'package:localize_and_translate/localize_and_translate.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:fuodz/extensions/context.dart';

class AddressSearchView extends StatefulWidget {
  const AddressSearchView(
    this.vm, {
    Key? key,
    this.addressSelected,
    this.selectOnMap,
  }) : super(key: key);

  //
  final dynamic vm;
  final Function(dynamic)? addressSelected;
  final Function? selectOnMap;

  @override
  _AddressSearchViewState createState() => _AddressSearchViewState();
}

class _AddressSearchViewState extends State<AddressSearchView> {
  //
  bool isLoading = false;
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];

  // novo: detalhes selecionados aguardando confirmação
  Map<String, dynamic>? _selectedDetails;

  // helper: chama autocomplete REST
  Future<void> _fetchPredictions(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    final apiKey = AppStrings.googleMapApiKey;
    print("DEBUG: Places autocomplete call with key: $apiKey input: $input");

    final components =
        (AppStrings.countryCode != null && AppStrings.countryCode.isNotEmpty)
            ? "&components=country:${AppStrings.countryCode}"
            : "";

    final url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$apiKey$components&types=geocode";

    try {
      final res = await http.get(Uri.parse(url)).timeout(Duration(seconds: 8));
      // tenta decodificar; se não for JSON válido, loga e retorna vazio
      dynamic body;
      try {
        body = json.decode(res.body);
      } catch (e) {
        print("DEBUG: autocomplete: resposta não é JSON -> ${res.body}");
        setState(() => _predictions = []);
        return;
      }

      if (body is Map) {
        print("DEBUG: autocomplete response status: ${body['status']}, error_message: ${body['error_message']}");
        if (body['status'] == 'OK' && body['predictions'] is List) {
          final preds = (body['predictions'] as List).map((p) {
            if (p is Map) {
              final desc = p['description'] ??
                  (p['structured_formatting'] is Map
                      ? p['structured_formatting']['main_text']
                      : null) ??
                  "";
              final placeId = p['place_id'] ?? p['placeId'] ?? "";
              return {
                "description": desc,
                "place_id": placeId,
              };
            }
            return {"description": "", "place_id": ""};
          }).where((p) => (p['place_id'] ?? "").toString().isNotEmpty).toList().cast<Map<String, dynamic>>();
          setState(() => _predictions = preds);
          return;
        } else {
          print("DEBUG: autocomplete sem resultados ou com erro -> ${body['error_message'] ?? body['status']}");
        }
      } else {
        print("DEBUG: autocomplete retornou formato inesperado: ${body.runtimeType}");
      }

      setState(() => _predictions = []);
    } catch (e, st) {
      print("DEBUG: autocomplete error -> $e\n$st");
      setState(() => _predictions = []);
    }
  }

  // helper: pega detalhes do place_id
  Future<Map<String, dynamic>?> _fetchPlaceDetails(String placeId) async {
    if (placeId.trim().isEmpty) {
      print("DEBUG: fetchPlaceDetails chamado com placeId vazio");
      return null;
    }
    final apiKey = AppStrings.googleMapApiKey;
    final url =
        "https://maps.googleapis.com/maps/api/place/details/json?place_id=${Uri.encodeComponent(placeId)}&key=$apiKey&fields=formatted_address,geometry";
    try {
      final res = await http.get(Uri.parse(url)).timeout(Duration(seconds: 8));
      dynamic body;
      try {
        body = json.decode(res.body);
      } catch (e) {
        print("DEBUG: place details: resposta não é JSON -> ${res.body}");
        return null;
      }

      if (body is Map) {
        print("DEBUG: place details status: ${body['status']}, error_message: ${body['error_message']}");
        if (body['status'] == 'OK' && body['result'] is Map) {
          final result = body['result'] as Map;
          final formatted = result['formatted_address'] ?? "";
          final geometry = result['geometry'];
          final location = (geometry is Map && geometry['location'] is Map) ? geometry['location'] : null;
          if (formatted != null && location != null && location['lat'] != null && location['lng'] != null) {
            return {
              "formatted_address": formatted,
              "lat": location['lat'],
              "lng": location['lng'],
            };
          } else {
            print("DEBUG: place details faltando geometry/formatted_address");
          }
        } else {
          print("DEBUG: place details erro -> ${body['error_message'] ?? body['status']}");
        }
      } else {
        print("DEBUG: place details retornou formato inesperado: ${body.runtimeType}");
      }
    } catch (e, st) {
      print("DEBUG: place details error -> $e\n$st");
    }
    return null;
  }

  // chamado ao digitar (debounce)
  void _onQueryChanged(String q) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(Duration(milliseconds: 500), () => _fetchPredictions(q));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // debug
    print("DEBUG: AddressSearchView -> googleMapApiKey: ${AppStrings.googleMapApiKey}");

    return VStack(
      [
        // campo de busca simples
        TextFormField(
          controller: widget.vm.placeSearchTEC,
          decoration: InputDecoration(
            hintText: "Enter your address...".tr(),
            prefixIcon: Icon(FlutterIcons.search_fea, size: 18),
          ),
          onChanged: _onQueryChanged,
        ).p8(),

        // lista de previsões
        if (_predictions.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: 250),
            child: ListView.separated(
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => Divider(height: 1),
              itemBuilder: (_, i) {
                final p = _predictions[i];
                return ListTile(
                  title: Text(p['description'] ?? ""),
                  onTap: () async {
                    // buscar detalhes e confirmar imediatamente ao tocar
                    setState(() {
                      isLoading = true;
                    });
                    final details = await _fetchPlaceDetails(p['place_id']);
                    setState(() {
                      isLoading = false;
                      _predictions = [];
                    });
                    if (details != null) {
                      final result = {
                        "addressLine": details['formatted_address'],
                        "latitude": details['lat'],
                        "longitude": details['lng'],
                      };
                      try {
                        widget.vm.addressTEC.text = result['addressLine'] ?? "";
                        widget.vm.placeSearchTEC.clear();
                        widget.vm.deliveryAddress ??= DeliveryAddress();
                        widget.vm.deliveryAddress!.address = result['addressLine'];
                        widget.vm.deliveryAddress!.latitude = result['latitude'];
                        widget.vm.deliveryAddress!.longitude = result['longitude'];
                        widget.vm.notifyListeners();
                      } catch (e) {
                        print("DEBUG: erro ao popular vm -> $e");
                      }
                      Navigator.of(context).pop(result);
                    } else {
                      context.showToast(msg: "Falha ao obter detalhes do lugar");
                    }
                  },
                );
              },
            ),
          ),

        // loader
        if (isLoading) BusyIndicator().centered().p20(),

        UiSpacer.expandedSpace(),

        // "Select on map" removido — não exibir opção de escolher no mapa
      ],
    ).p20().h(context.percentHeight * 90).scrollVertical();
  }
}
