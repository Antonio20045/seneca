import Foundation
import HealthKit

enum HealthStatistik {
    static var verfuegbar: Bool { HKHealthStore.isHealthDataAvailable() }
    private static let store = HKHealthStore()

    private static var typen: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.bodyMass),
         HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    static func mussFragen() async -> Bool {
        guard verfuegbar else { return false }
        return await withCheckedContinuation { c in
            store.getRequestStatusForAuthorization(toShare: [], read: typen) { status, _ in c.resume(returning: status == .shouldRequest) }
        }
    }

    static func anfragen() async {
        guard verfuegbar else { return }
        try? await store.requestAuthorization(toShare: [], read: typen)
    }

    private struct Aenderung { var neu: [HKSample]; var geloescht: [String]; var anker: Data? }

    private static func aenderung(_ typ: HKSampleType, _ pred: NSPredicate, anker: Data?) async -> Aenderung? {
        let a = anker.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        return await withCheckedContinuation { c in
            store.execute(HKAnchoredObjectQuery(type: typ, predicate: pred, anchor: a, limit: HKObjectQueryNoLimit) { _, neu, geloescht, neuerAnker, fehler in
                guard fehler == nil else { c.resume(returning: nil); return }
                let daten = neuerAnker.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
                c.resume(returning: Aenderung(neu: neu ?? [], geloescht: (geloescht ?? []).map { $0.uuid.uuidString }, anker: daten))
            })
        }
    }

    static func neueLaeufe(anker: Data?, seit: Date) async -> (neu: [StatLauf], geloescht: [String], anker: Data?)? {
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: seit, end: nil),
            HKQuery.predicateForWorkouts(with: .running),
        ])
        guard let a = await aenderung(HKObjectType.workoutType(), pred, anker: anker) else { return nil }
        return (a.neu.compactMap { ($0 as? HKWorkout).flatMap(grunddaten) }, a.geloescht, a.anker)
    }

    static func neueTrainings(anker: Data?, seit: Date) async -> (neu: [GeraetTraining], anker: Data?)? {
        guard let a = await aenderung(HKObjectType.workoutType(), HKQuery.predicateForSamples(withStart: seit, end: nil), anker: anker) else { return nil }
        let neu = a.neu.compactMap { $0 as? HKWorkout }.map { w in
            GeraetTraining(id: w.uuid.uuidString, start: w.startDate, ende: w.endDate, artNr: w.workoutActivityType.rawValue,
                           quelle: w.sourceRevision.source.name,
                           kcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                           meter: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()))
        }
        return (neu, a.anker)
    }

    private static func grunddaten(_ w: HKWorkout) -> StatLauf? {
        var meter = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
        if meter <= 0 { meter = w.totalDistance?.doubleValue(for: .meter()) ?? 0 }
        guard meter > 0, w.duration > 0 else { return nil }
        var kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        if kcal == nil || kcal == 0 { kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) }
        let aufstieg = (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
        return StatLauf(id: w.uuid.uuidString, start: w.startDate, dauer: w.duration, meter: meter,
                        kcal: kcal.flatMap { $0 > 0 ? $0.rounded() : nil }, aufstieg: aufstieg.flatMap { $0 > 0 ? $0.rounded() : nil },
                        quelle: w.sourceRevision.source.name)
    }

    static func neueGewichte(anker: Data?, seit: Date) async -> (neu: [String: StatGewichtProbe], geloescht: [String], anker: Data?)? {
        guard let a = await aenderung(HKQuantityType(.bodyMass), HKQuery.predicateForSamples(withStart: seit, end: nil), anker: anker) else { return nil }
        var neu: [String: StatGewichtProbe] = [:]
        for case let s as HKQuantitySample in a.neu {
            let kg = (s.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10).rounded() / 10
            if kg > 20, kg < 400 { neu[s.uuid.uuidString] = StatGewichtProbe(start: s.startDate, kg: kg) }
        }
        return (neu, a.geloescht, a.anker)
    }

    static func details(ids: [String]) async -> [String: StatLaufDetails] {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        let workouts: [HKWorkout] = await withCheckedContinuation { c in
            store.execute(HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObjects(with: uuids), limit: HKObjectQueryNoLimit,
                                        sortDescriptors: nil) { _, s, _ in c.resume(returning: (s as? [HKWorkout]) ?? []) })
        }
        return await withTaskGroup(of: (String, StatLaufDetails)?.self) { gruppe in
            for w in workouts { gruppe.addTask { await details(w).map { (w.uuid.uuidString, $0) } } }
            var alle: [String: StatLaufDetails] = [:]
            for await e in gruppe { if let e { alle[e.0] = e.1 } }
            return alle
        }
    }

    private static func details(_ w: HKWorkout) async -> StatLaufDetails? {
        let dieserLauf = HKQuery.predicateForObjects(from: w)

        let samples: [HKQuantitySample]? = await withCheckedContinuation { c in
            store.execute(HKSampleQuery(sampleType: HKQuantityType(.distanceWalkingRunning), predicate: dieserLauf, limit: HKObjectQueryNoLimit,
                                        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, fehler in
                c.resume(returning: fehler == nil ? ((s as? [HKQuantitySample]) ?? []) : nil)
            })
        }
        guard let samples else { return nil }
        let kmSamples = samples.map { StatKmSample(von: $0.startDate, bis: $0.endDate, meter: $0.quantity.doubleValue(for: .meter())) }

        let puls: (mittel: Double?, max: Double?)? = await withCheckedContinuation { c in
            let einheit = HKUnit.count().unitDivided(by: .minute())
            store.execute(HKStatisticsQuery(quantityType: HKQuantityType(.heartRate), quantitySamplePredicate: dieserLauf,
                                            options: [.discreteAverage, .discreteMax]) { _, s, fehler in
                if (fehler as? HKError)?.code == .errorDatabaseInaccessible { c.resume(returning: nil); return }
                c.resume(returning: (s?.averageQuantity()?.doubleValue(for: einheit), s?.maximumQuantity()?.doubleValue(for: einheit)))
            })
        }
        guard let puls else { return nil }
        return StatLaufDetails(kmZeiten: StatLaufRechnen.kmZeiten(kmSamples), pulsMittel: puls.mittel?.rounded(), pulsMax: puls.max?.rounded())
    }
}
