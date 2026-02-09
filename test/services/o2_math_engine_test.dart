import 'package:flutter_test/flutter_test.dart';
import 'package:o2_sentry/services/o2_math_engine.dart';

void main() {
  group('O2MathEngine.calculateFO2', () {
    test('air standard (mv == calMv) retourne 20.9', () {
      expect(O2MathEngine.calculateFO2(10.5, 10.5), closeTo(20.9, 0.01));
    });

    test('double mV retourne double FO2', () {
      expect(O2MathEngine.calculateFO2(21.0, 10.5), closeTo(41.8, 0.01));
    });

    test('currentMv = 0 retourne 0.0', () {
      expect(O2MathEngine.calculateFO2(0.0, 10.5), 0.0);
    });

    test('calMv = 0 (garde) retourne 20.9', () {
      expect(O2MathEngine.calculateFO2(10.5, 0.0), 20.9);
    });

    test('EAN32 typique ≈ 32.0', () {
      // 16.076 / 10.5 * 20.9 ≈ 32.0
      final result = O2MathEngine.calculateFO2(16.076, 10.5);
      expect(result, closeTo(32.0, 0.1));
    });

    test('sonde faible (8 mV) ≈ 15.9', () {
      // 8.0 / 10.5 * 20.9 ≈ 15.92
      expect(O2MathEngine.calculateFO2(8.0, 10.5), closeTo(15.92, 0.1));
    });
  });

  group('O2MathEngine.calculateMOD', () {
    test('air (20.9%) ppO2=1.4 ≈ 57m', () {
      // ((1.4 / 0.209) - 1) * 10 ≈ 56.97
      expect(O2MathEngine.calculateMOD(20.9, 1.4), closeTo(56.97, 0.1));
    });

    test('EAN32 ppO2=1.4 ≈ 33.75m', () {
      // ((1.4 / 0.32) - 1) * 10 ≈ 33.75
      expect(O2MathEngine.calculateMOD(32.0, 1.4), closeTo(33.75, 0.1));
    });

    test('EAN36 ppO2=1.6 ≈ 34.4m', () {
      // ((1.6 / 0.36) - 1) * 10 ≈ 34.44
      expect(O2MathEngine.calculateMOD(36.0, 1.6), closeTo(34.44, 0.1));
    });

    test('O2 pur ppO2=1.6 = 6.0m', () {
      // ((1.6 / 1.0) - 1) * 10 = 6.0
      expect(O2MathEngine.calculateMOD(100.0, 1.6), closeTo(6.0, 0.01));
    });

    test('fo2 = 0 (garde) retourne 0.0', () {
      expect(O2MathEngine.calculateMOD(0.0, 1.4), 0.0);
    });

    test('fo2 negatif (garde) retourne 0.0', () {
      expect(O2MathEngine.calculateMOD(-1.0, 1.4), 0.0);
    });
  });
}
