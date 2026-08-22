import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/configure_command.dart';
// ALIASED, and not by preference. `fluttersdk_artisan` exports its own
// toolchain `DoctorCommand` from the same barrel imported above, so an
// unprefixed import of this file makes every mention of `DoctorCommand` below
// ambiguous. Nothing warns about it until the file is written, and a `hide` on
// the artisan barrel would push the same problem onto whoever adds the next
// import here.
import 'commands/doctor_command.dart' as payments_doctor;
import 'commands/install_command.dart';

/// The `fluttersdk_artisan` provider for Magic Payments.
///
/// Contributes the three `payments:*` commands to the host application. A
/// consumer registers it beside the other plugin providers in its
/// `artisan.providers` config.
///
/// ## The MCP surface is one tool, and that is a policy
///
/// Only `payments_doctor` is exposed. `payments:install` and
/// `payments:configure` MUTATE the consumer's source tree, and across this
/// ecosystem a mutating command is deliberately absent from the MCP surface: an
/// agent that can rewrite `lib/config/app.dart` and `lib/main.dart` without a
/// human at the keyboard is a different risk from one that can read a report.
/// Adding either here is a policy change, not a convenience.
class PaymentsArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'payments';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
    InstallCommand(),
    ConfigureCommand(),
    payments_doctor.DoctorCommand(),
  ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
    McpToolDescriptor(
      name: 'payments_doctor',
      description:
          'Check the Magic Payments installation and configuration of the '
          'project in the current working directory.\n\n'
          'Runs six checks, each reading one file: the magic_payments '
          'dependency in pubspec.yaml, its resolution in '
          '.dart_tool/package_config.json, the presence of '
          'lib/config/payments.dart, the payments root and driver value inside '
          'it, the PaymentsServiceProvider entry in lib/config/app.dart, and '
          'the paymentsConfig entry in lib/main.dart configFactories.\n\n'
          'It does NOT report which payment rail a build can serve: that is '
          'decided by a conditional import at compile time, so no CLI process '
          'can read the answer for a platform it is not compiled for.\n\n'
          'Usage:\n'
          '- Call with no arguments for the report and a pass/fail exit code.\n'
          '- Set verbose to true to also print the path and the requirement '
          'behind each check.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'verbose': <String, dynamic>{
            'type': 'boolean',
            'description':
                'Print the path and the requirement behind each check. '
                'Default: false.',
          },
        },
      },
      extensionMethod: 'artisan:payments:doctor',
    ),
  ];
}
