import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:anycast/states/user.dart';

void main() {
  test('Google Firebase credential uses the ID token without an access token',
      () {
    const authentication = GoogleSignInAuthentication(
      idToken: 'test-id-token',
    );

    final credential =
        firebaseCredentialFromGoogleAuthentication(authentication);

    expect(credential.idToken, 'test-id-token');
    expect(credential.accessToken, isNull);
  });
}
