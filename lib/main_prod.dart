import 'flavors/app_flavor.dart';
import 'main.dart' as app;

Future<void> main(List<String> args) async {
  FlavorConfig.setFlavor(AppFlavor.prod);
  await app.bootstrap(args: args);
}
