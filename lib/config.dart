/// Paste your Supabase project values here.
/// Supabase Dashboard > Project Settings > API
class AppConfig {
  static const supabaseUrl = 'https://ofvpqdqnvmgdnyyjgevi.supabase.co';

  /// Publishable key (sb_publishable_...) or the legacy "anon public" key.
  /// Never put the secret / service_role key in the app.
  static const supabaseKey = 'sb_publishable_RvQpyV_zxZxws9EAwSF1HQ_ZUq5xbRI';

  /// Firebase (Android push alerts for admins). From google-services.json:
  /// api_key.current_key, client_info.mobilesdk_app_id,
  /// project_info.project_number, project_info.project_id.
  /// Leave empty to switch trip alerts off.
  static const firebaseApiKey = 'AIzaSyCJ1_ilSZm-vjj99-qAOpo8g6sgkk9T5HI';
  static const firebaseAppId = '1:510671429700:android:d495440d43dbd76c219c11';
  static const firebaseSenderId = '510671429700';
  static const firebaseProjectId = 'trip-logbook-54a17';

  static const appName = 'Trip Logbook';
  static const currency = 'PKR';
}
