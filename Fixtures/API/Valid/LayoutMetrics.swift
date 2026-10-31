import Stana

func layoutMetricFixture(_ metrics: STNMetrics) -> [Int] {
	[
		metrics.measureCalls,
		metrics.placedNodes,
		metrics.measureVisits,
		metrics.measureCacheHits,
		metrics.textMeasureCalls,
		metrics.placementVisits,
		metrics.layoutOutputChanges,
		metrics.arrangedChildVisits,
		metrics.flexDistributionRounds,
		metrics.layoutDirtyAncestorVisits,
	]
}
