# Code Review — flutter-tvos

**Дата:** 2026-04-16  
**Покрытие:** весь репозиторий (lib/, packages/, bin/, templates/, pubspec.yaml)  
**Метод:** статический анализ + ручное чтение кода  
**Статус:** 10 реальных багов, 10 ложных срабатываний отброшено

---

## Сводка

| Приоритет | Кол-во |
|-----------|--------|
| Высокий   | 3      |
| Средний   | 4      |
| Низкий    | 3      |

---

## Высокий приоритет

### BUG-1 — `stopApp` не останавливает приложение на физическом устройстве

**Файл:** `lib/tvos_device.dart:497–504`

**Проблема:**  
Команда `devicectl device process terminate` вызывается с `--pid 0`. PID 0 — зарезервированный системный процесс ядра. Команда либо вернёт ошибку, либо завершит что-то непредсказуемое. Комментарий `// Will terminate by bundle ID below` вводит в заблуждение — кода "ниже" нет, реализация незавершённая. Приложение на физическом Apple TV никогда не останавливается при вызове `flutter-tvos`.

```dart
// Текущий код:
final RunResult result = await globals.processUtils.run(<String>[
  'xcrun', 'devicectl', 'device', 'process', 'terminate',
  '--device', id,
  '--pid', '0', // Will terminate by bundle ID below
]);
return result.exitCode == 0;
```

**Исправление:**
```dart
final RunResult result = await globals.processUtils.run(<String>[
  'xcrun', 'devicectl', 'device', 'process', 'terminate',
  '--device', id,
  '--bundle-id', app.id,
]);
return result.exitCode == 0;
```

---

### BUG-9 — Версия приложения всегда `1.0.0 (1)`

**Файл:** `lib/build_targets/application.dart:613–614`

**Проблема:**  
`Generated.xcconfig` генерируется с захардкоженными константами, игнорируя `pubspec.yaml` пользователя. Любое приложение, собранное через `flutter-tvos build`, будет иметь версию `1.0.0 (1)` в App Store Connect. При попытке залить вторую версию Apple отклонит билд — "build with this version already exists".

```dart
// Текущий код:
xcconfig.writeln('FLUTTER_BUILD_NAME=1.0.0');
xcconfig.writeln('FLUTTER_BUILD_NUMBER=1');
```

**Исправление:**
```dart
xcconfig.writeln('FLUTTER_BUILD_NAME=${buildInfo.buildInfo.buildName}');
xcconfig.writeln('FLUTTER_BUILD_NUMBER=${buildInfo.buildInfo.buildNumber}');
```

---

### BUG-16 — `installApp` игнорирует режим сборки

**Файл:** `lib/tvos_device.dart:246, 258`

**Проблема:**  
`installApp` хардкодит `BuildMode.debug` для симулятора и `BuildMode.release` для физического устройства. При запуске `flutter-tvos run --release` на симуляторе код ищет bundle по пути `Debug-appletvsimulator/Runner.app`, тогда как собранный файл находится в `Release-appletvsimulator/`. Установка тихо падает с "file not found".

```dart
// Текущий код:
// Симулятор — всегда debug:
final String appPath = tvosApp.bundlePath(BuildMode.debug, isSimulator: true);
// Физическое устройство — всегда release:
final String appPath = tvosApp.bundlePath(BuildMode.release, isSimulator: false);
```

**Исправление:**  
Передавать `BuildMode` через параметр или читать из `DebuggingOptions` в `startApp`, пробрасывая в `installApp`.

---

## Средний приоритет

### BUG-7 — Doctor показывает `success` при ненастроенном окружении

**Файл:** `lib/tvos_doctor.dart:70–81`

**Проблема:**  
Две ошибки в логике `ValidationType`:

1. `hasErrors → ValidationType.partial` — должно быть `missing`. Если tvOS SDK не найден, нельзя разрабатывать вообще. Пользователь видит жёлтый `[!]` вместо красного `[✗]`.
2. `hasHints → ValidationType.success` — если CocoaPods не установлен, doctor добавляет hint и возвращает зелёную галочку. Плагины с нативным кодом при этом не соберутся.

В сочетании с BUG-8 эффект усиливается: doctor всегда зелёный, даже если `precache` не запускался.

```dart
// Текущий код:
if (hasErrors) {
  validationType = ValidationType.partial;   // ← неверно
} else if (hasHints) {
  validationType = ValidationType.success;   // ← неверно
}
```

**Исправление:**
```dart
if (hasErrors) {
  validationType = ValidationType.missing;
} else if (hasHints) {
  validationType = ValidationType.partial;
}
```

---

### BUG-8 — Doctor всегда сообщает "артефакты не найдены"

**Файл:** `lib/tvos_doctor.dart:189–193`

**Проблема:**  
`ls -d engine_artifacts/tvos_debug_sim_arm64` выполняется с относительным путём без `workingDirectory`. Команда запускается в CWD процесса — директории проекта пользователя (`~/projects/my_app/`), а не в директории CLI-инструмента. Проверка всегда завершается с ошибкой, и doctor всегда показывает:

```
! tvOS engine artifacts not found. Run: flutter-tvos precache
```

Даже если `precache` уже был выполнен.

```dart
// Текущий код:
final ProcessResult result = await _processManager.run(<String>[
  'ls', '-d',
  'engine_artifacts/tvos_debug_sim_arm64',  // относительный путь
]);
```

**Исправление:**
```dart
final Directory artifactDir = tvosArtifactDirectory(globals.fs);
final ProcessResult result = await _processManager.run(<String>[
  'ls', '-d',
  artifactDir.childDirectory('tvos_debug_sim_arm64').path,
]);
```

---

### BUG-3 — `_sdkPath` не проверяет exitCode

**Файл:** `lib/build_targets/application.dart:593–598`

**Проблема:**  
Если `xcrun --show-sdk-path` завершается с ошибкой (нет Xcode, неверный SDK), метод возвращает пустую строку. Она передаётся как `-isysroot ""` в вызовы компилятора при AOT-сборке. Сборка падает с непонятной ошибкой компилятора вместо внятного "SDK not found".

```dart
// Текущий код:
Future<String> _sdkPath(String sdkName) async {
  final ProcessResult result = await globals.processManager.run(
    <String>['xcrun', '--sdk', sdkName, '--show-sdk-path'],
  );
  return (result.stdout as String).trim();  // exitCode игнорируется
}
```

**Исправление:**
```dart
Future<String> _sdkPath(String sdkName) async {
  final ProcessResult result = await globals.processManager.run(
    <String>['xcrun', '--sdk', sdkName, '--show-sdk-path'],
  );
  if (result.exitCode != 0) {
    throwToolExit('xcrun --show-sdk-path failed for $sdkName:\n${result.stderr}');
  }
  return (result.stdout as String).trim();
}
```

---

### BUG-18 — `TypeError` при невалидном JSON из simctl не перехватывается

**Файл:** `lib/tvos_emulator.dart:33–54`

**Проблема:**  
В Dart `TypeError` (результат неудачного cast `as`) является `Error`, а не `Exception`. Блок `on Exception catch (e)` его не поймает. Если Apple изменит формат вывода `simctl list devices --json`, первый же невалидный cast (`as Map<String, dynamic>`, `as String`) бросит необработанный `TypeError` и уронит `flutter-tvos devices` со stack trace.

```dart
// Текущий код:
try {
  final Map<String, dynamic> json = jsonDecode(result.stdout) as Map<String, dynamic>;
  final Map<String, dynamic> sim = simulator as Map<String, dynamic>;
  devices.add(TvosDevice(
    sim['udid'] as String,   // TypeError если поле отсутствует или другого типа
    ...
  ));
} on Exception catch (e) {  // ← не поймает TypeError
  logger.printTrace('Error querying simctl: $e');
}
```

**Исправление:**
```dart
} catch (Object e) {
  logger.printTrace('Error querying simctl: $e');
}
```

---

## Низкий приоритет

### BUG-17 — Regex `platforms:` в `create` может сломать pubspec.yaml

**Файл:** `lib/commands/create.dart:158–164`

**Проблема:**  
`firstMatch` ищет первое вхождение слова `platforms:` в файле. Если в pubspec.yaml есть комментарий вида `# Supports multiple platforms:` или любое другое вхождение этого слова, код вставит `tvos:` в неверное место, сломав структуру YAML. Отступ `8 пробелов` также захардкожен — при других отступах YAML-структура нарушится.

```dart
// Текущий код:
final RegExp platformsRegex = RegExp(r'(platforms:\s*\n)', multiLine: true);
final Match? match = platformsRegex.firstMatch(content);  // первое вхождение
```

**Исправление:**  
Искать `platforms:` только внутри блока `flutter.plugin`, используя более специфичный regex или парсинг через пакет `yaml`.

---

### BUG-19 — Не потокобезопасная инициализация в FFI

**Файл:** `packages/flutter_tvos/tvos/Classes/flutter_tvos_ffi.m:18–38`

**Проблема:**  
`_ensure_initialized()` использует простой флаг `s_initialized` без `dispatch_once` или мьютекса. При одновременном вызове из нескольких Dart Isolate возможна гонка: два потока одновременно увидят `s_initialized == false` и оба начнут записывать в статические char-буферы `s_system_version[256]` и другие. Это data race — неопределённое поведение в C.

```c
// Текущий код:
static bool s_initialized = false;

static void _ensure_initialized(void) {
    if (s_initialized) return;   // не атомарно
    s_initialized = true;
    // заполняем буферы...
}
```

**Исправление:**
```objc
static dispatch_once_t s_once_token;

static void _ensure_initialized(void) {
    dispatch_once(&s_once_token, ^{
        // заполняем буферы...
    });
}
```

---

### BUG-20 — `pubspec.yaml` без version constraints

**Файл:** `pubspec.yaml:12–31`

**Проблема:**  
Все зависимости объявлены без версионных constraints (`analyzer:`, `archive:`, `http:` и т.д.). При `pub get` без lock-файла (CI, новый разработчик) будут взяты последние версии, которые могут содержать breaking changes. Дополнительно: `fake_async` находится в `dependencies` вместо `dev_dependencies`.

```yaml
# Текущий код:
dependencies:
  analyzer:
  archive:
  fake_async:   # ← должен быть в dev_dependencies
  http:
  ...
```

**Исправление:**  
Добавить явные constraints для всех зависимостей и перенести тестовые пакеты в `dev_dependencies`.

---

## Отброшенные ложные срабатывания

| # | Описание | Причина отклонения |
|---|----------|--------------------|
| 2 | stderr симулятора парсится как JSON | `_onUnifiedLoggingLine` корректно игнорирует non-JSON строки через regex |
| 4 | `startLogStream` без bundleID | Мёртвый код — нигде не вызывается в реальном flow |
| 5 | Unsafe cast `as TvosArtifacts` | DI в `executable.dart` гарантирует правильный тип в production |
| 6 | `tvosValidator!` NPE | Оба типа явно зарегистрированы в `executable.dart` |
| 10 | `.symlinks` удаляется как файл | `file.existsSync()` вернёт false для директории — не крашит, просто не очищает |
| 11 | Code injection через `pluginClass` | Требует намеренно вредоносный пакет от самого разработчика |
| 12 | Предсказуемое имя temp-файла | Надуманный сценарий для локального CLI-инструмента |
| 13 | Нет integrity check артефактов | Стандарт для Flutter CLI; не уникальный баг |
| 14 | nullptr в FFI перед `toDartString()` | Нативные функции возвращают статические буферы, никогда не NULL |
| 15 | `argResults!.rest.first` RangeError | `super.runCommand()` валидирует аргументы до возврата |
