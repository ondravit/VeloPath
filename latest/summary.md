# CI run 7 – baf3416 (rebuild-v2)

| step | outcome |
|---|---|
| core tests | success |
| simulator build | success |
| screenshots | success |
| UI tests | success |
| unsigned IPA | success |

## Compiler errors
```
```
## UI tests
```
Test Case '-[VeloPathUITests.VeloPathUITests testPlanRouteByTappingAndExport]' passed (52.026 seconds).
Test Case '-[VeloPathUITests.VeloPathUITests testSearchAddsWaypoint]' passed (29.396 seconds).
Test Case '-[VeloPathUITests.VeloPathUITests testSettingsShowAttribution]' passed (26.458 seconds).
```
## Core test summary
```
Test Suite 'All tests' started at 2026-11-19 13:19:04.879.
Test Suite 'VeloCorePackageTests.xctest' started at 2026-11-19 13:19:04.889.
Test Suite 'GPXWriterTests' started at 2026-11-19 13:19:04.889.
Test Case '-[VeloCoreTests.GPXWriterTests testDocumentStructure]' passed (0.048 seconds).
Test Suite 'GPXWriterTests' passed at 2026-11-19 13:19:04.938.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.048 (0.049) seconds
Test Suite 'RouterTests' started at 2026-11-19 13:19:04.938.
Test Case '-[VeloCoreTests.RouterTests testCancellation]' passed (0.006 seconds).
Test Case '-[VeloCoreTests.RouterTests testClimbHysteresis]' passed (0.000 seconds).
Test Case '-[VeloCoreTests.RouterTests testGraphLoads]' passed (0.000 seconds).
Test Case '-[VeloCoreTests.RouterTests testLoadingFromDataMatchesMappedFile]' passed (0.002 seconds).
Test Case '-[VeloCoreTests.RouterTests testMultiLegRoute]' passed (0.022 seconds).
Test Case '-[VeloCoreTests.RouterTests testOneWayStreetsAreRespected]' passed (0.016 seconds).
Test Case '-[VeloCoreTests.RouterTests testRejectsGarbage]' passed (0.000 seconds).
Test Case '-[VeloCoreTests.RouterTests testRouterIsReusable]' passed (0.040 seconds).
Test Case '-[VeloCoreTests.RouterTests testRoutesMatchReference]' passed (0.221 seconds).
Test Case '-[VeloCoreTests.RouterTests testRoutingPerformance]' passed (0.709 seconds).
Test Case '-[VeloCoreTests.RouterTests testSnapFarAwayFails]' passed (0.000 seconds).
Test Case '-[VeloCoreTests.RouterTests testSnapMatchesReference]' passed (0.027 seconds).
Test Suite 'RouterTests' passed at 2026-11-19 13:19:05.986.
	 Executed 12 tests, with 0 failures (0 unexpected) in 1.044 (1.047) seconds
Test Suite 'VeloCorePackageTests.xctest' passed at 2026-11-19 13:19:05.986.
	 Executed 13 tests, with 0 failures (0 unexpected) in 1.092 (1.096) seconds
Test Suite 'All tests' passed at 2026-11-19 13:19:05.986.
	 Executed 13 tests, with 0 failures (0 unexpected) in 1.092 (1.107) seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```
