import Foundation

// MARK: - ENT Subspecialty

enum ENTSubspecialty: String, Codable, CaseIterable, Sendable {
    case headAndNeck = "Head & Neck"
    case otology = "Otology"
    case rhinology = "Rhinology"
    case pediatricENT = "Pediatric ENT"
    case laryngology = "Laryngology"
}

// MARK: - Case Difficulty

enum CaseDifficulty: String, Codable, CaseIterable, Sendable, Comparable {
    case straightforward
    case intermediate
    case challenging

    private var sortOrder: Int {
        switch self {
        case .straightforward: return 0
        case .intermediate: return 1
        case .challenging: return 2
        }
    }

    static func < (lhs: CaseDifficulty, rhs: CaseDifficulty) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Clinical Case Model

struct ClinicalCase: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    let title: String
    let subspecialty: ENTSubspecialty
    let difficulty: CaseDifficulty
    let clinicalVignette: String
    let keyHistoryPoints: [String]
    let examinationFindings: [String]
    let investigations: [String]
    let managementPlan: [String]
    let criticalPoints: [String]
    let teachingNotes: String
    let tags: [String]
}

// MARK: - ClinicalCase → DocumentAnalysis Conversion

extension ClinicalCase {
    func toAnalysis() -> DocumentAnalysis {
        let topicDifficulty: ExamTopic.Difficulty = switch difficulty {
        case .straightforward: .foundational
        case .intermediate: .intermediate
        case .challenging: .advanced
        }

        let topicAreas: [(String, Double, [String])] = [
            ("History & Presentation", 0.8, keyHistoryPoints),
            ("Clinical Examination", 0.9, examinationFindings),
            ("Investigations", 0.7, investigations),
            ("Management", 0.95, managementPlan),
            ("Critical Safety Points", 1.0, criticalPoints)
        ]

        let topics = topicAreas
            .filter { !$0.2.isEmpty }
            .map { name, importance, concepts in
                ExamTopic(
                    name: name,
                    importance: importance,
                    keyConcepts: concepts,
                    difficulty: topicDifficulty,
                    subtopics: tags
                )
            }

        let questionCount: Int = switch difficulty {
        case .straightforward: 8
        case .intermediate: 12
        case .challenging: 16
        }

        let duration: Int = switch difficulty {
        case .straightforward: 10
        case .intermediate: 15
        case .challenging: 20
        }

        return DocumentAnalysis(
            topics: topics,
            documentSummary: "\(title): \(clinicalVignette)",
            suggestedQuestionCount: questionCount,
            estimatedDurationMinutes: duration,
            difficultyAssessment: difficulty.rawValue
        )
    }
}

// MARK: - Case Bank

struct CaseBank {

    // MARK: - Queries

    static func cases(for subspecialty: ENTSubspecialty) -> [ClinicalCase] {
        allCases.filter { $0.subspecialty == subspecialty }
    }

    static func cases(difficulty: CaseDifficulty) -> [ClinicalCase] {
        allCases.filter { $0.difficulty == difficulty }
    }

    static func randomCase(
        subspecialty: ENTSubspecialty? = nil,
        difficulty: CaseDifficulty? = nil
    ) -> ClinicalCase? {
        var filtered = allCases
        if let subspecialty {
            filtered = filtered.filter { $0.subspecialty == subspecialty }
        }
        if let difficulty {
            filtered = filtered.filter { $0.difficulty == difficulty }
        }
        return filtered.randomElement()
    }

    // MARK: - All Cases

    static let allCases: [ClinicalCase] = headAndNeckCases
        + otologyCases
        + rhinologyCases
        + pediatricENTCases

    // MARK: - Head & Neck Cases

    private static let headAndNeckCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "A0000001-0001-0001-0001-000000000001")!,
            title: "Parotid Pleomorphic Adenoma",
            subspecialty: .headAndNeck,
            difficulty: .intermediate,
            clinicalVignette: """
                A 45-year-old woman presents with a slow-growing, painless lump \
                in the left parotid region, first noticed 18 months ago. She has \
                no facial weakness, and the lump is firm, mobile, and approximately \
                3 cm in diameter.
                """,
            keyHistoryPoints: [
                "Duration and rate of growth — slow growth over months favours benign pathology",
                "Pain or facial nerve symptoms — absence suggests benign tumour",
                "History of previous skin cancers or irradiation to the head and neck",
                "Smoking and alcohol history for completeness",
                "Any recent rapid enlargement suggesting malignant transformation"
            ],
            examinationFindings: [
                "Firm, smooth, mobile 3 cm lump in the superficial lobe of the left parotid",
                "No facial nerve weakness (test all branches of CN VII)",
                "No fixation to skin or deep structures",
                "Bimanual palpation to assess deep lobe extension",
                "Full head and neck examination including the neck for lymphadenopathy",
                "Inspect the oropharynx for deep lobe parapharyngeal extension"
            ],
            investigations: [
                "Ultrasound of the parotid — well-defined, lobulated, heterogeneous mass",
                "Fine needle aspiration cytology (FNAC) — Milan classification",
                "MRI parotid with gadolinium for deep lobe assessment and surgical planning",
                "CT if MRI contraindicated; assess bony involvement"
            ],
            managementPlan: [
                "Superficial parotidectomy with facial nerve dissection and preservation",
                "Intraoperative facial nerve monitoring",
                "Identify the facial nerve trunk using landmarks: tragal pointer, tympanomastoid suture, posterior belly of digastric",
                "Ensure complete excision with a cuff of normal tissue to reduce recurrence",
                "Discuss risk of Frey syndrome, facial nerve injury (temporary and permanent), wound complications",
                "Long-term follow-up as recurrence may occur years later"
            ],
            criticalPoints: [
                "Must assess facial nerve function before and after surgery",
                "Must not perform enucleation alone — high recurrence rate",
                "Must consider malignant transformation risk if left untreated",
                "Must discuss recurrence risk (1–5% after adequate parotidectomy, up to 40% after enucleation)"
            ],
            teachingNotes: """
                Pleomorphic adenoma is the most common salivary gland tumour. \
                The key surgical principle is complete excision with a cuff of \
                normal tissue. Enucleation leads to unacceptable recurrence rates \
                because the tumour has pseudopod extensions through an incomplete \
                capsule. Multinodular recurrence is extremely difficult to manage.
                """,
            tags: ["parotid", "salivary gland", "facial nerve", "surgery", "benign tumour"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "A0000001-0001-0001-0001-000000000002")!,
            title: "Laryngeal Squamous Cell Carcinoma",
            subspecialty: .headAndNeck,
            difficulty: .challenging,
            clinicalVignette: """
                A 62-year-old male with a 40-pack-year smoking history presents \
                with progressive hoarseness for 6 weeks. He denies dysphagia, \
                odynophagia, or weight loss. Flexible nasendoscopy reveals an \
                exophytic lesion on the left true vocal cord with impaired cord mobility.
                """,
            keyHistoryPoints: [
                "Duration and progression of hoarseness — any voice change beyond 3 weeks needs laryngoscopy",
                "Smoking and alcohol history — synergistic risk factors",
                "Dysphagia, odynophagia, referred otalgia as markers of advanced disease",
                "Weight loss suggesting systemic involvement",
                "Previous head and neck malignancy or radiotherapy",
                "Occupational exposures (asbestos, wood dust)"
            ],
            examinationFindings: [
                "Flexible nasendoscopy: exophytic lesion on left true vocal cord, impaired mobility",
                "Assess bilateral cord movement — impaired mobility suggests T2 or T3 staging",
                "Palpate neck for cervical lymphadenopathy (levels II–VI)",
                "Examine oral cavity and oropharynx for synchronous primaries",
                "Assess voice quality and airway adequacy"
            ],
            investigations: [
                "Microlaryngoscopy and biopsy under general anaesthesia — histological confirmation",
                "CT neck and thorax with contrast — staging, nodal disease, lung metastases",
                "MRI larynx for cartilage invasion assessment if equivocal on CT",
                "PET-CT if advanced disease suspected",
                "Panendoscopy to exclude synchronous primary (10% risk in aerodigestive tract)"
            ],
            managementPlan: [
                "MDT discussion — head and neck surgeon, oncologist, speech therapist, CNS",
                "T2 glottic SCC: primary radiotherapy offers excellent cure with voice preservation (80–90% control)",
                "Alternative: transoral laser microsurgery (TLM) for selected T2 lesions",
                "Discuss voice outcomes, follow-up schedule, salvage laryngectomy if recurrence",
                "Smoking cessation counselling — continued smoking worsens radiotherapy outcomes",
                "Speech and language therapy assessment pre- and post-treatment",
                "Nutritional support if required during treatment"
            ],
            criticalPoints: [
                "Must stage the tumour accurately — cord fixity distinguishes T2 from T3",
                "Must discuss in MDT before definitive treatment",
                "Must exclude synchronous primaries with panendoscopy",
                "Must counsel about voice preservation versus oncological safety",
                "Must have salvage laryngectomy as a backup plan and discuss this with the patient"
            ],
            teachingNotes: """
                Glottic SCC has the best prognosis of laryngeal cancers because \
                the true cords have minimal lymphatic drainage, making nodal \
                metastasis uncommon in early disease. The key debate is between \
                primary radiotherapy (voice preservation) and TLM. Both offer \
                comparable oncological outcomes for T1–T2 disease. Always assess \
                cord mobility carefully — it changes stage and management entirely.
                """,
            tags: ["larynx", "SCC", "voice preservation", "radiotherapy", "MDT", "smoking"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "A0000001-0001-0001-0001-000000000003")!,
            title: "Thyroid Nodule — Papillary Carcinoma",
            subspecialty: .headAndNeck,
            difficulty: .intermediate,
            clinicalVignette: """
                A 38-year-old woman is referred after an incidental 2.2 cm thyroid \
                nodule found on carotid Doppler ultrasound. She is clinically \
                euthyroid with no compressive symptoms. There is no family history \
                of thyroid cancer and no radiation exposure.
                """,
            keyHistoryPoints: [
                "How the nodule was discovered — incidental finding on imaging",
                "Compressive symptoms: dysphagia, dyspnoea, voice change",
                "Thyroid dysfunction symptoms — hyper or hypothyroid features",
                "Family history of thyroid cancer or MEN syndromes",
                "History of head and neck irradiation in childhood",
                "Rate of growth if previously known"
            ],
            examinationFindings: [
                "Palpable 2 cm firm nodule in the right lobe of the thyroid",
                "Moves with swallowing, no fixation to surrounding structures",
                "No cervical lymphadenopathy",
                "No signs of thyroid dysfunction (tremor, tachycardia, eye signs)",
                "Flexible nasendoscopy to assess vocal cord mobility pre-operatively"
            ],
            investigations: [
                "Thyroid function tests — TSH, free T4 (confirm euthyroid status)",
                "Ultrasound with U-classification — hypoechoic, microcalcifications, taller-than-wide suspicious features (U4/U5)",
                "Ultrasound-guided FNAC — Bethesda classification (Thy1–Thy5 / Bethesda I–VI)",
                "If Bethesda V/VI (Thy4/Thy5) — proceed to surgery",
                "CT neck and thorax if concern about extrathyroidal extension or nodal disease"
            ],
            managementPlan: [
                "Total thyroidectomy for confirmed papillary carcinoma > 1 cm",
                "Consider diagnostic hemithyroidectomy if Bethesda III/IV (Thy3)",
                "Central neck dissection if clinically or radiologically evident nodal disease",
                "Post-operative radioiodine ablation for intermediate/high-risk disease",
                "Lifelong levothyroxine for TSH suppression (target depends on risk stratification)",
                "Thyroglobulin as tumour marker in follow-up",
                "Follow-up ultrasound of thyroid bed and neck at 6–12 months"
            ],
            criticalPoints: [
                "Must check vocal cord function (flexible nasendoscopy) before thyroid surgery",
                "Must classify FNAC using Bethesda/Thy system and act accordingly",
                "Must discuss risk of recurrent laryngeal nerve injury and hypoparathyroidism",
                "Must stratify risk (ATA guidelines) to guide adjuvant treatment"
            ],
            teachingNotes: """
                Papillary thyroid carcinoma carries an excellent prognosis (>95% \
                10-year survival for low-risk disease). The Bethesda system \
                standardises FNAC reporting and guides management. Key surgical \
                complications to counsel about are recurrent laryngeal nerve palsy \
                (1–2% permanent) and hypoparathyroidism (1–3% permanent). Molecular \
                testing (e.g., BRAF, ThyroSeq) is increasingly used for \
                indeterminate cytology.
                """,
            tags: ["thyroid", "papillary carcinoma", "FNAC", "Bethesda", "thyroidectomy", "radioiodine"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "A0000001-0001-0001-0001-000000000004")!,
            title: "Neck Lump in a Young Adult",
            subspecialty: .headAndNeck,
            difficulty: .straightforward,
            clinicalVignette: """
                A 25-year-old man presents with a 3-week history of a painless, \
                2 cm mass in the left posterior triangle of the neck. He has no \
                constitutional symptoms but reports recent upper respiratory tract \
                infection. He is a non-smoker and otherwise well.
                """,
            keyHistoryPoints: [
                "Duration — under 6 weeks may be reactive; over 6 weeks raises suspicion",
                "Associated symptoms: night sweats, weight loss, pruritus (B-symptoms of lymphoma)",
                "Recent infections — EBV, CMV, dental abscess, TB contacts",
                "Smoking and alcohol — even in young adults, always ask",
                "Travel history and TB exposure",
                "Previous malignancy or immunosuppression"
            ],
            examinationFindings: [
                "2 cm firm, non-tender, mobile lymph node in left level V",
                "No overlying skin changes, no fixation",
                "Full head and neck examination including scalp (draining territory for posterior triangle)",
                "Examine all nodal groups: cervical, axillary, inguinal",
                "Examine the abdomen for hepatosplenomegaly",
                "Check for Waldeyer's ring enlargement (tonsils, base of tongue, nasopharynx)"
            ],
            investigations: [
                "Full blood count — lymphocytosis, anaemia",
                "LDH, ESR, CRP — raised in lymphoma",
                "Monospot/EBV serology if clinically suspected",
                "Ultrasound-guided FNAC as initial investigation",
                "Core biopsy or excision biopsy if FNAC suspicious or non-diagnostic (lymphoma requires tissue architecture)",
                "CT neck, chest, abdomen, pelvis if lymphoma confirmed for staging"
            ],
            managementPlan: [
                "If reactive: observe for 4–6 weeks with safety-netting advice",
                "If persistent or growing: excision biopsy preferred (do NOT incision biopsy if lymphoma suspected)",
                "Refer to haematology if lymphoma confirmed",
                "Use a systematic approach to neck lumps: anatomical site, age, duration, and clinical features",
                "Safety-net with clear advice on when to return (growth, new lumps, B-symptoms)"
            ],
            criticalPoints: [
                "Must ask about red flag B-symptoms: night sweats, weight loss, unexplained fever",
                "Must examine all lymph node groups and for organomegaly",
                "Must obtain tissue diagnosis if the lump persists beyond 6 weeks",
                "Must not perform incision biopsy for suspected lymphoma — excision biopsy gives architecture"
            ],
            teachingNotes: """
                The approach to a neck lump is structured by age: in children \
                think congenital and inflammatory, in young adults think \
                inflammatory and lymphoma, in older adults think malignancy until \
                proved otherwise. The posterior triangle is a high-risk site for \
                malignancy. An open biopsy giving tissue architecture is essential \
                for lymphoma subtyping.
                """,
            tags: ["neck lump", "lymphoma", "lymphadenopathy", "biopsy", "differential diagnosis"]
        )
    ]

    // MARK: - Otology Cases

    private static let otologyCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "B0000001-0001-0001-0001-000000000001")!,
            title: "Cholesteatoma",
            subspecialty: .otology,
            difficulty: .intermediate,
            clinicalVignette: """
                A 50-year-old man presents with a 6-month history of foul-smelling \
                right ear discharge and progressive hearing loss. He has a long \
                history of recurrent otitis media. Otoscopy reveals an attic \
                retraction pocket with white debris.
                """,
            keyHistoryPoints: [
                "Nature and duration of discharge — foul-smelling, scanty, persistent suggests cholesteatoma",
                "Hearing loss — type (conductive vs mixed) and progression",
                "History of recurrent ear infections or previous ear surgery",
                "Vertigo or balance disturbance suggesting labyrinthine erosion",
                "Facial weakness suggesting facial nerve involvement",
                "Headache or neurological symptoms suggesting intracranial complication"
            ],
            examinationFindings: [
                "Attic retraction pocket (pars flaccida) with trapped keratin debris",
                "Foul-smelling, scanty discharge on microsuction",
                "Conductive hearing loss on tuning fork tests (Rinne negative, Weber lateralises to affected ear)",
                "Assess facial nerve function (House–Brackmann grade)",
                "Assess for fistula sign (positive suggests lateral semicircular canal erosion)",
                "Examine contralateral ear"
            ],
            investigations: [
                "Pure tone audiogram — conductive or mixed hearing loss",
                "High-resolution CT temporal bone — soft tissue in the epitympanum, erosion of scutum, ossicular chain disruption",
                "MRI with diffusion-weighted imaging (DWI) — distinguishes cholesteatoma from granulation (restricted diffusion)",
                "DWI MRI also used post-operatively to detect residual or recurrent disease"
            ],
            managementPlan: [
                "Surgical excision: combined approach tympanoplasty (canal wall up) or modified radical mastoidectomy (canal wall down)",
                "Canal wall up preserves anatomy but has higher residual/recurrence rates — needs second look or MRI surveillance",
                "Canal wall down creates a mastoid cavity requiring lifelong care but lower recurrence",
                "Ossiculoplasty for hearing reconstruction (staged or simultaneous)",
                "Post-operative MRI DWI surveillance at 12 months if canal wall up technique used",
                "Long-term audiological follow-up"
            ],
            criticalPoints: [
                "Must assess and document facial nerve function before surgery",
                "Must recognise and manage complications: facial nerve palsy, labyrinthine fistula, intracranial sepsis",
                "Must not treat with antibiotics alone — cholesteatoma requires surgical management",
                "Must counsel that cholesteatoma is a progressive, destructive condition if untreated"
            ],
            teachingNotes: """
                Cholesteatoma is not a true neoplasm but an abnormal collection of \
                keratinising squamous epithelium that erodes bone by enzymatic \
                activity and pressure. The key surgical decision is canal wall up \
                versus canal wall down — this depends on extent of disease, surgeon \
                experience, and patient factors. DWI MRI has transformed follow-up \
                by reducing the need for second-look surgery.
                """,
            tags: ["cholesteatoma", "mastoid surgery", "conductive hearing loss", "otitis media", "temporal bone"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0001-0001-0001-000000000002")!,
            title: "Sudden Sensorineural Hearing Loss",
            subspecialty: .otology,
            difficulty: .intermediate,
            clinicalVignette: """
                A 42-year-old woman wakes up with profound hearing loss in the \
                right ear and a sensation of fullness. She reports accompanying \
                tinnitus but no vertigo. She has no significant past medical \
                history and takes no regular medication.
                """,
            keyHistoryPoints: [
                "Onset — sudden (within 72 hours) suggests vascular, viral, or autoimmune aetiology",
                "Associated tinnitus and aural fullness — common accompaniments",
                "Vertigo — if present, may indicate worse prognosis or labyrinthitis",
                "History of recent viral illness",
                "Previous ear surgery or noise exposure",
                "Cardiovascular risk factors and autoimmune conditions",
                "Contralateral hearing status"
            ],
            examinationFindings: [
                "Normal otoscopy (tympanic membrane intact, no effusion)",
                "Tuning fork tests: Rinne positive bilaterally, Weber lateralises to the LEFT (away from the affected ear)",
                "Document facial nerve function (normal)",
                "Cranial nerve examination — all normal",
                "Romberg test and gait assessment"
            ],
            investigations: [
                "Urgent pure tone audiogram — confirms sensorineural hearing loss (≥30 dB over 3 consecutive frequencies)",
                "Bloods: FBC, ESR, CRP, glucose, lipid profile, autoimmune screen (ANA, ANCA, anti-dsDNA), syphilis serology",
                "MRI internal auditory meatus with gadolinium — to exclude vestibular schwannoma (essential investigation)",
                "Tympanometry — to exclude conductive component"
            ],
            managementPlan: [
                "Commence high-dose oral corticosteroids within 72 hours (e.g., prednisolone 1 mg/kg for 7–14 days with taper)",
                "Intratympanic steroid injection if systemic steroids fail or are contraindicated",
                "MRI IAMs to exclude retrocochlear pathology (vestibular schwannoma in ~1%)",
                "Audiological follow-up with serial audiograms to monitor recovery",
                "Hearing rehabilitation: hearing aid or CROS aid if no recovery",
                "Consider cochlear implant referral if bilateral profound loss",
                "Reassurance and counselling about prognosis (one-third recover fully, one-third partial, one-third none)"
            ],
            criticalPoints: [
                "Must treat as an otological emergency — delay worsens prognosis",
                "Must obtain MRI to exclude vestibular schwannoma",
                "Must not diagnose as wax or Eustachian tube dysfunction without audiometry",
                "Must commence steroids within 72 hours for best outcome"
            ],
            teachingNotes: """
                Sudden SNHL is defined as ≥30 dB loss over 3 consecutive frequencies \
                occurring within 72 hours. The cause is idiopathic in ~90% of cases. \
                Early steroid treatment is the single most important intervention. \
                The crucial diagnosis to exclude is vestibular schwannoma — about 1% \
                of sudden SNHL presentations are caused by this. Never assume a \
                unilateral sensorineural hearing loss is benign without imaging.
                """,
            tags: ["sudden hearing loss", "SNHL", "steroids", "vestibular schwannoma", "audiometry", "emergency"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0001-0001-0001-000000000003")!,
            title: "Vestibular Schwannoma",
            subspecialty: .otology,
            difficulty: .challenging,
            clinicalVignette: """
                A 55-year-old man is referred with a 2-year history of progressive \
                left-sided hearing loss and constant tinnitus. He describes \
                occasional unsteadiness but no true vertigo. MRI reveals a 2.5 cm \
                enhancing lesion in the left cerebellopontine angle.
                """,
            keyHistoryPoints: [
                "Progressive unilateral hearing loss — hallmark symptom",
                "Unilateral tinnitus — persistent and non-pulsatile",
                "Balance disturbance — usually unsteadiness rather than episodic vertigo",
                "Facial numbness (trigeminal involvement with large tumours)",
                "Family history of neurofibromatosis type 2 (bilateral VS, young age)",
                "Impact on daily life, employment, and contralateral hearing status"
            ],
            examinationFindings: [
                "Pure tone audiogram: left-sided high-frequency sensorineural hearing loss",
                "Reduced speech discrimination disproportionate to pure tone thresholds (retrocochlear pattern)",
                "Normal facial nerve function (House–Brackmann grade I)",
                "Assess trigeminal sensation and corneal reflex (large tumours)",
                "Cerebellar signs: past-pointing, dysdiadochokinesis if large CPA tumour",
                "Examine the contralateral ear and hearing"
            ],
            investigations: [
                "MRI IAMs/CPA with gadolinium — 2.5 cm enhancing lesion in the left CPA with extension into the IAM (ice cream cone appearance)",
                "Pure tone audiogram and speech audiometry — asymmetric SNHL with poor speech discrimination",
                "Auditory brainstem response (ABR) — prolonged wave I–V interwave latency",
                "CT temporal bone if surgery planned — assess labyrinthine anatomy",
                "Caloric testing — reduced vestibular response on the affected side"
            ],
            managementPlan: [
                "Three options: observation (watch–wait–rescan), microsurgery, stereotactic radiosurgery (SRS/Gamma Knife)",
                "Watch–wait–rescan: serial MRI at 6 months then annually; appropriate for small tumours or elderly patients",
                "Microsurgery: retrosigmoid, translabyrinthine, or middle fossa approach depending on size and hearing status",
                "Translabyrinthine approach for non-serviceable hearing — best facial nerve outcomes",
                "Retrosigmoid approach if hearing preservation attempted",
                "SRS (Gamma Knife): for tumours <3 cm, good tumour control (~95%), preserves hearing in 50–70%",
                "Intraoperative facial nerve monitoring is mandatory for surgical cases",
                "Multidisciplinary discussion between ENT surgeon and neurosurgeon"
            ],
            criticalPoints: [
                "Must exclude NF2 — bilateral vestibular schwannomas, family history, age <30",
                "Must discuss all three management options with the patient",
                "Must counsel about facial nerve risk with surgery (relates to tumour size)",
                "Must assess contralateral hearing — critical for management decisions",
                "Must use intraoperative facial nerve monitoring if surgery is chosen"
            ],
            teachingNotes: """
                Vestibular schwannomas account for 80% of CPA tumours. The natural \
                history is variable — some grow, some remain stable, and a few \
                shrink. The translabyrinthine approach sacrifices hearing but gives \
                the best access and facial nerve outcomes. Gamma Knife offers \
                excellent tumour control for small-to-medium tumours. The key to \
                the viva is demonstrating a balanced, patient-centred discussion \
                of all three management options with their respective trade-offs.
                """,
            tags: ["vestibular schwannoma", "acoustic neuroma", "CPA", "facial nerve", "Gamma Knife", "microsurgery"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0001-0001-0001-000000000004")!,
            title: "Otitis Media with Effusion in Children",
            subspecialty: .otology,
            difficulty: .straightforward,
            clinicalVignette: """
                A 4-year-old boy is referred by his GP with bilateral hearing \
                loss noticed by his parents over the past 4 months. He attends \
                nursery and has had multiple upper respiratory tract infections. \
                Tympanometry shows bilateral flat (type B) traces.
                """,
            keyHistoryPoints: [
                "Duration of hearing loss — at least 3 months for OME to be considered persistent",
                "Speech and language development — any delay or regression",
                "Impact on behaviour, social interaction, and education",
                "Frequency of upper respiratory tract infections and ear infections",
                "Snoring, mouth breathing, or sleep-disordered breathing (adenoid hypertrophy)",
                "Family history of glue ear",
                "Unilateral OME in adult — must consider post-nasal space pathology"
            ],
            examinationFindings: [
                "Otoscopy: dull, retracted tympanic membranes with visible fluid levels or air bubbles",
                "Tympanometry: bilateral type B (flat) traces confirming effusions",
                "Free-field hearing assessment or audiogram: bilateral conductive hearing loss (typically 20–30 dB)",
                "Assess adenoid facies: mouth breathing, elongated face",
                "Examine the oral cavity and oropharynx for tonsillar hypertrophy"
            ],
            investigations: [
                "Tympanometry — type B bilateral (confirms effusion)",
                "Pure tone audiogram or free-field testing — conductive hearing loss, typically 20–30 dB HL",
                "No imaging required routinely in paediatric bilateral OME",
                "In adults with unilateral OME: flexible nasendoscopy and consider MRI/CT nasopharynx to exclude malignancy"
            ],
            managementPlan: [
                "Active observation for 3 months — 50% resolve spontaneously",
                "Autoinflation (Otovent balloon) as a conservative measure",
                "Grommet (ventilation tube) insertion if persistent (≥3 months) with hearing loss and developmental impact",
                "Adjunctive adenoidectomy if recurrent OME after grommets or if significant adenoid hypertrophy",
                "Hearing aids as alternative to surgery if parents decline or anaesthetic risk",
                "Post-operative follow-up: check grommets at 6 weeks and until they extrude (typically 6–12 months)",
                "Advise parents on speech and language monitoring"
            ],
            criticalPoints: [
                "Must assess the impact on speech and language development",
                "Must observe for at least 3 months before surgical intervention (NICE guidelines)",
                "Must counsel parents about natural history — most resolve spontaneously",
                "Must be aware of grommet complications: otorrhoea, early extrusion, persistent perforation"
            ],
            teachingNotes: """
                OME is the most common cause of hearing loss in children (peak age \
                2–5 years). The key to management is assessing impact rather than \
                the effusion itself. Not all children with OME need grommets — only \
                those with persistent bilateral effusions causing hearing loss that \
                affects development. Adenoidectomy reduces recurrence by improving \
                Eustachian tube function. Always consider an underlying cause for \
                unilateral OME in adults.
                """,
            tags: ["OME", "glue ear", "grommets", "children", "hearing loss", "adenoidectomy"]
        )
    ]

    // MARK: - Rhinology Cases

    private static let rhinologyCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0001-0001-0001-000000000001")!,
            title: "Severe Epistaxis",
            subspecialty: .rhinology,
            difficulty: .straightforward,
            clinicalVignette: """
                A 72-year-old man on warfarin for atrial fibrillation presents to \
                the emergency department with a 2-hour history of profuse anterior \
                epistaxis from the right nostril. Initial first aid has been \
                unsuccessful, and he is haemodynamically stable.
                """,
            keyHistoryPoints: [
                "Duration and severity of the bleed — amount of blood loss, haemodynamic status",
                "Anticoagulant and antiplatelet medications — warfarin, DOACs, aspirin, clopidogrel",
                "Previous episodes of epistaxis and any treatment received",
                "History of hypertension, liver disease, coagulopathy",
                "Family history of bleeding disorders — consider Osler–Weber–Rendu (HHT)",
                "Recent nasal surgery, trauma, or nasal spray use"
            ],
            examinationFindings: [
                "Active bleeding from right Little's area (Kiesselbach's plexus) — most common site",
                "Assess haemodynamic stability: blood pressure, heart rate",
                "Anterior rhinoscopy after clearing clot with suction",
                "Assess for posterior bleeding source if anterior source not identified",
                "Look for telangiectasia on lips, tongue, and nasal mucosa (HHT screen)",
                "Full cardiovascular examination including blood pressure"
            ],
            investigations: [
                "Full blood count — haemoglobin, platelet count",
                "Coagulation screen — PT/INR (target INR for warfarin patients)",
                "Group and save if significant haemorrhage",
                "Renal function and liver function if coagulopathy suspected",
                "CT angiography if considering sphenopalatine artery ligation for refractory posterior epistaxis"
            ],
            managementPlan: [
                "First aid: sit forward, pinch the cartilaginous nose firmly for 20 minutes without releasing",
                "Topical treatment: silver nitrate cautery to visible anterior bleeding point (one side only per session)",
                "If cautery fails: Rapid Rhino or Merocel anterior nasal pack",
                "Posterior packing with Foley catheter or posterior balloon if anterior packing fails",
                "Correct coagulopathy: hold warfarin, consider vitamin K, discuss with haematology re bridging anticoagulation",
                "Surgical intervention if packing fails: sphenopalatine artery ligation (endoscopic) or anterior ethmoidal artery ligation",
                "Interventional radiology embolisation as an alternative in high-risk patients",
                "Address underlying cause: optimise blood pressure, review anticoagulation, screen for HHT"
            ],
            criticalPoints: [
                "Must assess and maintain haemodynamic stability — this can be life-threatening",
                "Must check and correct INR/coagulopathy",
                "Must have a stepwise escalation plan: first aid → cautery → packing → surgical",
                "Must not cauterise both sides of the septum simultaneously — perforation risk"
            ],
            teachingNotes: """
                Ninety percent of epistaxis is anterior (Little's area) and \
                manageable with first aid or cautery. Posterior epistaxis is less \
                common but more difficult to control and often requires packing or \
                surgical intervention. Sphenopalatine artery ligation has \
                transformed the management of refractory posterior epistaxis with \
                success rates above 95%. Always manage anticoagulation carefully \
                — the reason for anticoagulation matters as much as stopping the bleed.
                """,
            tags: ["epistaxis", "nosebleed", "anticoagulation", "warfarin", "sphenopalatine artery", "emergency"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "C0000001-0001-0001-0001-000000000002")!,
            title: "Septal Perforation",
            subspecialty: .rhinology,
            difficulty: .intermediate,
            clinicalVignette: """
                A 35-year-old man is referred with a 6-month history of nasal \
                crusting, intermittent epistaxis, and an audible nasal whistle on \
                breathing. Anterior rhinoscopy reveals a 1.5 cm perforation in \
                the anterior nasal septum.
                """,
            keyHistoryPoints: [
                "Nasal symptoms: crusting, epistaxis, whistling, obstruction, dryness",
                "Previous nasal surgery — septoplasty is the commonest iatrogenic cause",
                "Cocaine use — must ask directly and sensitively (common cause in younger patients)",
                "Nasal spray use — topical corticosteroids, decongestants",
                "Systemic symptoms: joint pains, skin rashes, renal symptoms (vasculitis screen)",
                "Occupational exposure to chrome, arsenic, or industrial chemicals",
                "History of nasal cautery or trauma"
            ],
            examinationFindings: [
                "Anterior rhinoscopy: 1.5 cm perforation in the anterior cartilaginous septum",
                "Assess the edges — crusted, clean, or inflamed margins",
                "Size and location of the perforation (anterior vs posterior, cartilaginous vs bony)",
                "Examine for saddle nose deformity (cartilage destruction in vasculitis or cocaine use)",
                "Nasal endoscopy: assess remaining septum, turbinates, and sinonasal mucosa",
                "General examination: skin lesions, joint swelling, chest signs"
            ],
            investigations: [
                "ANCA (c-ANCA / PR3 for granulomatosis with polyangiitis; p-ANCA / MPO for eosinophilic GPA)",
                "ESR, CRP — inflammatory markers",
                "Syphilis serology (RPR/VDRL, TPHA)",
                "Urine dipstick for haematuria and proteinuria (renal involvement in vasculitis)",
                "Biopsy of perforation edge if granulomatous disease suspected",
                "Urine drug screen if cocaine use suspected but denied",
                "CT sinuses if associated sinonasal disease"
            ],
            managementPlan: [
                "Treat the underlying cause — cessation of cocaine, adjust nasal sprays, treat vasculitis",
                "Conservative management: saline irrigations, nasal emollients, humidification to reduce crusting",
                "Septal button (prosthetic obturator) for symptomatic relief if surgery not appropriate",
                "Surgical repair for suitable candidates: local mucosal flaps, temporalis fascia interposition, acellular dermal grafts",
                "Smaller anterior perforations (<2 cm) have best surgical success rates (>90%)",
                "Ensure disease is quiescent before attempting surgical repair",
                "If vasculitis confirmed: immunosuppressive therapy guided by rheumatology"
            ],
            criticalPoints: [
                "Must exclude granulomatosis with polyangiitis (Wegener's) — check ANCA",
                "Must sensitively enquire about cocaine use",
                "Must not attempt surgical repair in active disease — high failure rate",
                "Must biopsy the edge of the perforation if the cause is uncertain"
            ],
            teachingNotes: """
                The three most common causes of septal perforation are iatrogenic \
                (septoplasty), cocaine use, and granulomatosis with polyangiitis. \
                The key investigation is ANCA — a positive c-ANCA/PR3 is highly \
                specific for GPA. Surgical repair success depends on size \
                (small > large), location (anterior > posterior), and quiescent \
                disease. The viva examiner will expect you to have a systematic \
                approach to aetiology.
                """,
            tags: ["septal perforation", "ANCA", "vasculitis", "cocaine", "septoplasty", "GPA"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "C0000001-0001-0001-0001-000000000003")!,
            title: "Sinonasal Inverted Papilloma",
            subspecialty: .rhinology,
            difficulty: .challenging,
            clinicalVignette: """
                A 48-year-old man presents with progressive unilateral left nasal \
                obstruction and intermittent bloody nasal discharge over 8 months. \
                Nasal endoscopy reveals a papillomatous mass originating from the \
                left lateral nasal wall. A CT scan shows a soft tissue mass with \
                focal hyperostosis at the left maxillary sinus ostium.
                """,
            keyHistoryPoints: [
                "Unilateral nasal obstruction — key red flag for neoplasm",
                "Bloody discharge — must differentiate from simple epistaxis",
                "Duration and progression of symptoms",
                "Anosmia or hyposmia",
                "Previous nasal polyp surgery or sinus surgery (recurrence is common)",
                "No significant association with smoking (unlike SCC)",
                "HPV association (types 6, 11, and rarely 16, 18)"
            ],
            examinationFindings: [
                "Nasal endoscopy: cerebriform or papillomatous mass on the left lateral nasal wall",
                "Unilateral disease — distinguishes from bilateral inflammatory polyps",
                "Assess extent: middle meatus, maxillary sinus, ethmoids",
                "Examine the contralateral side (usually normal)",
                "Neck examination for lymphadenopathy (malignant transformation)",
                "Cranial nerve examination"
            ],
            investigations: [
                "CT sinuses: unilateral soft tissue opacification with focal hyperostosis at the site of tumour attachment",
                "MRI sinuses with gadolinium: convoluted cerebriform pattern on T2/contrast (characteristic striated pattern distinguishes from polyps and malignancy)",
                "Biopsy under endoscopic guidance — confirms inverted papilloma, assess for dysplasia or SCC",
                "Staging: Krouse classification (T1–T4) based on extent of disease"
            ],
            managementPlan: [
                "Endoscopic medial maxillectomy for tumours arising from the lateral nasal wall/maxillary sinus (Krouse T1–T3)",
                "Complete excision with drilling of the bone at the site of attachment to reduce recurrence",
                "Open approaches (lateral rhinotomy, Caldwell–Luc, midfacial degloving) for extensive disease or revision cases",
                "If associated SCC found: oncological resection with clear margins and adjuvant radiotherapy",
                "Long-term endoscopic surveillance — recurrence rates 0–15% after adequate endoscopic resection",
                "Follow-up endoscopy at 3, 6, 12 months then annually for at least 5 years"
            ],
            criticalPoints: [
                "Must recognise unilateral nasal mass as a red flag — not a simple polyp",
                "Must obtain histology to exclude malignant transformation (5–15% harbour SCC)",
                "Must identify the site of tumour attachment (origin) for surgical planning",
                "Must counsel about recurrence risk and need for long-term follow-up"
            ],
            teachingNotes: """
                Inverted papilloma accounts for about 0.5–4% of nasal tumours. The \
                pathognomonic feature on imaging is focal hyperostosis at the site \
                of attachment, which guides surgical planning. The convoluted \
                cerebriform pattern on MRI T2 is characteristic. The key surgical \
                principle is complete excision including the underlying bone at the \
                attachment site. The risk of synchronous or metachronous SCC (5–15%) \
                mandates long-term surveillance.
                """,
            tags: ["inverted papilloma", "sinonasal", "endoscopic surgery", "Krouse staging", "malignant transformation"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "C0000001-0001-0001-0001-000000000004")!,
            title: "Chronic Rhinosinusitis with Nasal Polyps",
            subspecialty: .rhinology,
            difficulty: .intermediate,
            clinicalVignette: """
                A 45-year-old woman presents with bilateral nasal obstruction, \
                anosmia, and frontal pressure for over 12 months. She has a \
                background of adult-onset asthma and aspirin sensitivity. Nasal \
                endoscopy reveals bilateral grade 3 nasal polyps.
                """,
            keyHistoryPoints: [
                "Cardinal symptoms of CRS: nasal obstruction, discharge, facial pain/pressure, hyposmia/anosmia (≥12 weeks defines chronic)",
                "Asthma history — severity, control, inhaler use (asthma-polyps association)",
                "Aspirin or NSAID sensitivity — Samter's triad (aspirin-exacerbated respiratory disease, AERD)",
                "Previous sinus surgery and number of recurrences",
                "Allergies and allergy testing",
                "Impact on quality of life (SNOT-22 score)",
                "Smoking status"
            ],
            examinationFindings: [
                "Nasal endoscopy: bilateral grade 3 polyps (polyps below the inferior turbinate)",
                "Pale, oedematous, grape-like mucosal swellings arising from the middle meatus",
                "Reduced or absent nasal airflow bilaterally",
                "Post-nasal drip visible in the oropharynx",
                "Examine the chest: wheeze may indicate poorly controlled asthma"
            ],
            investigations: [
                "CT sinuses (Lund–Mackay scoring): bilateral opacification of ethmoid, maxillary, and possibly frontal and sphenoid sinuses",
                "SNOT-22 quality of life questionnaire — baseline and post-treatment comparison",
                "Skin prick testing or specific IgE — identify allergic triggers",
                "Total IgE and eosinophil count — elevated in type 2 inflammatory phenotype",
                "Consider ANCA if unilateral or atypical features (exclude vasculitis)",
                "Consider CF testing if young patient with nasal polyps"
            ],
            managementPlan: [
                "Maximal medical therapy first: intranasal corticosteroid spray (long-term), saline irrigations, short course of oral prednisolone for flares",
                "Aspirin desensitisation if AERD confirmed — reduces polyp recurrence",
                "Functional endoscopic sinus surgery (FESS) if maximal medical therapy fails — open sinuses, remove polyps, improve topical drug delivery",
                "Biologic therapy for recurrent polyps with type 2 inflammation: dupilumab (anti-IL-4/IL-13), omalizumab (anti-IgE), mepolizumab (anti-IL-5)",
                "Post-operative maintenance with topical steroids (irrigations or sprays) and saline",
                "Optimise asthma management in conjunction with respiratory physician",
                "Long-term follow-up — polyps tend to recur, especially in AERD"
            ],
            criticalPoints: [
                "Must recognise Samter's triad (AERD): nasal polyps, asthma, aspirin sensitivity",
                "Must trial maximal medical therapy before offering FESS",
                "Must have a plan for recurrence — biologics are changing the landscape",
                "Must exclude sinister unilateral pathology if asymmetric (inverted papilloma, malignancy)"
            ],
            teachingNotes: """
                CRS with nasal polyps is a type 2 inflammatory condition driven by \
                eosinophils, IL-4, IL-5, and IL-13. Samter's triad (AERD) is the \
                classic high-recurrence phenotype. Biologics (dupilumab in \
                particular) have transformed the management of recalcitrant polyps \
                — SINUS-24 and SINUS-52 trials showed significant reductions in \
                polyp score, nasal obstruction, and need for surgery. This is a \
                rapidly evolving area the examiner will expect you to know.
                """,
            tags: ["CRS", "nasal polyps", "FESS", "Samter's triad", "AERD", "biologics", "dupilumab"]
        )
    ]

    // MARK: - Pediatric ENT Cases

    private static let pediatricENTCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0001-0001-0001-000000000001")!,
            title: "Tonsillectomy — Indications and Complications",
            subspecialty: .pediatricENT,
            difficulty: .straightforward,
            clinicalVignette: """
                A 5-year-old girl is referred with recurrent tonsillitis (7 episodes \
                in the past year) and symptoms of obstructive sleep apnoea including \
                loud snoring, witnessed apnoeas, and daytime somnolence. Her tonsils \
                are grade 4 and kissing in the midline.
                """,
            keyHistoryPoints: [
                "Number and frequency of tonsillitis episodes — Paradise criteria (7 in 1 year, 5/year for 2 years, or 3/year for 3 years)",
                "Sleep-disordered breathing symptoms: snoring, witnessed apnoeas, restless sleep, mouth breathing, enuresis",
                "Daytime symptoms: somnolence, poor concentration, behavioural issues",
                "Impact on school attendance and quality of life",
                "History of peritonsillar abscess",
                "Bleeding history and family history of bleeding disorders"
            ],
            examinationFindings: [
                "Grade 4 tonsils (kissing tonsils, meeting in the midline)",
                "Friedman tongue position assessment",
                "Examine the adenoid pad with flexible nasendoscopy (often enlarged in this age group)",
                "Assess for adenoid facies: mouth breathing, elongated face, dental malocclusion",
                "Growth parameters — failure to thrive in severe OSA",
                "Chest examination: pectus excavatum in chronic upper airway obstruction"
            ],
            investigations: [
                "Sleep study (polysomnography or overnight oximetry) if OSA is the primary indication — confirms severity",
                "FBC and coagulation screen pre-operatively",
                "No routine imaging required",
                "Consider lateral soft tissue neck X-ray or nasendoscopy for adenoid assessment"
            ],
            managementPlan: [
                "Tonsillectomy (with or without adenoidectomy) — meets both OSA and recurrent tonsillitis indications",
                "Surgical technique: cold steel dissection, bipolar diathermy, coblation — surgeon preference",
                "Post-operative care: analgesia (paracetamol, ibuprofen; avoid codeine in children), oral fluids, diet as tolerated",
                "Post-tonsillectomy haemorrhage management: primary (<24 hours) or secondary (day 5–10)",
                "Secondary haemorrhage protocol: assess in ED, IV access, group and save, return to theatre if active bleeding or clot in fossa",
                "Overnight observation recommended for children under 3 or with severe OSA (risk of post-obstructive pulmonary oedema)"
            ],
            criticalPoints: [
                "Must know the Paradise criteria for recurrent tonsillitis",
                "Must counsel about post-tonsillectomy haemorrhage risk (2–4%) and the need to return urgently",
                "Must avoid codeine and aspirin in children post-tonsillectomy",
                "Must be aware of OSA-related perioperative risks: desaturation, pulmonary oedema"
            ],
            teachingNotes: """
                Tonsillectomy is one of the most commonly performed ENT operations. \
                Post-tonsillectomy haemorrhage remains the most feared complication \
                — secondary haemorrhage typically occurs between days 5–10 when the \
                slough separates from the tonsillar fossa. Children with severe OSA \
                need close post-operative monitoring as they can develop \
                post-obstructive pulmonary oedema from the sudden change in \
                intrathoracic pressure dynamics.
                """,
            tags: ["tonsillectomy", "OSA", "Paradise criteria", "post-tonsillectomy haemorrhage", "children"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "D0000001-0001-0001-0001-000000000002")!,
            title: "Pediatric Stridor — Croup vs Epiglottitis",
            subspecialty: .pediatricENT,
            difficulty: .intermediate,
            clinicalVignette: """
                A 3-year-old boy is brought to the emergency department at 2 AM with \
                a barking cough, inspiratory stridor, and hoarse voice. Symptoms \
                started with a coryzal illness 2 days ago and worsened acutely \
                tonight. He has a low-grade fever of 38.2°C and is maintaining his \
                oxygen saturations at 95% in air.
                """,
            keyHistoryPoints: [
                "Age — croup peaks at 6 months to 3 years; epiglottitis is now rare due to Hib vaccination",
                "Onset — croup has a prodromal coryza then worsens at night; epiglottitis has a rapid, toxic onset",
                "Character of stridor: inspiratory (supraglottic/glottic), biphasic (subglottic), expiratory (intrathoracic)",
                "Drooling, dysphagia, inability to swallow — suggests epiglottitis or supraglottic pathology",
                "Vaccination history — is Hib vaccination up to date?",
                "Previous episodes of croup (recurrent croup warrants further investigation)",
                "Foreign body aspiration history — sudden onset without prodrome"
            ],
            examinationFindings: [
                "Assess severity using Westley croup score: stridor, retractions, air entry, cyanosis, level of consciousness",
                "Barking (seal-like) cough — pathognomonic of croup",
                "Hoarse voice with croup; muffled (hot potato) voice with epiglottitis",
                "Child with croup is usually comfortable at rest; child with epiglottitis sits upright, drooling, anxious",
                "Do NOT examine the throat if epiglottitis is suspected — may precipitate complete obstruction",
                "Oxygen saturations, respiratory rate, heart rate, temperature"
            ],
            investigations: [
                "Croup is a clinical diagnosis — investigations only if diagnosis uncertain or severe",
                "AP neck X-ray (if needed): steeple sign (subglottic narrowing) in croup",
                "Lateral neck X-ray: thumb sign (swollen epiglottis) in epiglottitis — obtain only if child is stable",
                "Bloods: not required routinely for croup; blood cultures if epiglottitis suspected",
                "Flexible nasendoscopy: only in controlled setting (theatre) if epiglottitis suspected"
            ],
            managementPlan: [
                "Mild croup (Westley score 0–2): single dose of oral dexamethasone (0.15 mg/kg), observe, discharge with safety-netting",
                "Moderate croup (Westley 3–5): dexamethasone (0.6 mg/kg oral or IM), nebulised adrenaline (0.5 mL/kg of 1:1000, max 5 mL) if not improving",
                "Severe croup (Westley ≥6): nebulised adrenaline, dexamethasone, high-flow oxygen, call anaesthetist and ENT for possible intubation",
                "Nebulised adrenaline effect is transient (2 hours) — observe for rebound",
                "Epiglottitis management: do NOT distress the child, summon senior anaesthetist, ENT, and paediatrician; inhalational induction in theatre, intubate, IV antibiotics (ceftriaxone), HDU/ICU",
                "Recurrent croup (>2 episodes): investigate for subglottic stenosis, haemangioma, or reflux with microlaryngobronchoscopy"
            ],
            criticalPoints: [
                "Must differentiate croup from epiglottitis — different urgency and management",
                "Must not examine the throat if epiglottitis is suspected",
                "Must call for senior anaesthetic help early in severe stridor",
                "Must observe for at least 2 hours after nebulised adrenaline for rebound"
            ],
            teachingNotes: """
                Croup (laryngotracheobronchitis) is the most common cause of \
                paediatric stridor, caused by parainfluenza virus in most cases. \
                Dexamethasone has transformed management — even a single dose \
                reduces severity, need for return visits, and intubation rates. \
                Epiglottitis is now rare thanks to Hib vaccination but still occurs \
                (non-typeable Haemophilus, Strep species) — the key point is to \
                maintain a calm environment and secure the airway under controlled \
                conditions.
                """,
            tags: ["croup", "epiglottitis", "stridor", "paediatric airway", "dexamethasone", "emergency"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "D0000001-0001-0001-0001-000000000003")!,
            title: "Thyroglossal Duct Cyst",
            subspecialty: .pediatricENT,
            difficulty: .intermediate,
            clinicalVignette: """
                An 8-year-old girl presents with a painless midline neck mass that \
                has been present for several months. Her mother reports it moves \
                upward when the child swallows or protrudes her tongue. There has \
                been one episode of redness and swelling suggesting infection.
                """,
            keyHistoryPoints: [
                "Duration and growth pattern of the mass",
                "Movement with swallowing and tongue protrusion — pathognomonic of thyroglossal duct cyst",
                "Episodes of infection or abscess formation",
                "Thyroid function symptoms — ensure functioning thyroid tissue elsewhere",
                "Family history of thyroid disease",
                "Previous neck surgery"
            ],
            examinationFindings: [
                "2 cm smooth, non-tender, midline or paramedian mass at the level of the hyoid bone",
                "Elevates with tongue protrusion (pathognomonic — tests connection to foramen caecum via thyroglossal duct remnant)",
                "Elevates with swallowing",
                "Transillumination may be positive (cystic)",
                "Palpate for a normal thyroid gland in the usual position",
                "No cervical lymphadenopathy"
            ],
            investigations: [
                "Ultrasound of the neck: cystic midline mass, confirm normal thyroid gland in situ (essential before surgery)",
                "Thyroid function tests — confirm euthyroid status",
                "No FNAC needed unless solid component raises concern for ectopic thyroid tissue or carcinoma (1% risk)",
                "Thyroid nuclear scan only if thyroid not visualised on ultrasound — exclude ectopic thyroid (only functioning thyroid tissue)"
            ],
            managementPlan: [
                "Sistrunk procedure — excision of the cyst, the central portion of the hyoid bone, and a core of tissue to the foramen caecum",
                "Simple cyst excision alone has a high recurrence rate (50%) — Sistrunk reduces this to <5%",
                "If infected: treat infection with antibiotics first, then proceed with elective Sistrunk procedure once resolved",
                "Do NOT incise and drain (creates a sinus tract that complicates later surgery)",
                "Histological examination of specimen — 1% risk of papillary carcinoma arising in a thyroglossal duct cyst",
                "Post-operative follow-up: wound check, monitor for recurrence"
            ],
            criticalPoints: [
                "Must confirm a normal thyroid gland is present before excision — avoid removing the patient's only thyroid tissue",
                "Must perform Sistrunk procedure (not simple excision) to reduce recurrence",
                "Must not incise and drain an infected thyroglossal duct cyst",
                "Must send specimen for histology — rare papillary carcinoma risk"
            ],
            teachingNotes: """
                The thyroglossal duct cyst is the most common congenital midline \
                neck mass, arising from remnants of the thyroglossal duct along \
                the embryological descent path of the thyroid. The relationship to \
                the hyoid bone is key — the duct passes through or anterior to the \
                hyoid, so the Sistrunk procedure (removing the central hyoid) \
                eliminates the entire tract. The differential diagnosis of a midline \
                neck mass in a child includes dermoid cyst and submental lymph node.
                """,
            tags: ["thyroglossal duct cyst", "Sistrunk", "congenital", "midline neck mass", "hyoid bone"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "D0000001-0001-0001-0001-000000000004")!,
            title: "Inhaled Foreign Body in a Child",
            subspecialty: .pediatricENT,
            difficulty: .straightforward,
            clinicalVignette: """
                A 2-year-old boy is brought to the emergency department after a \
                sudden choking episode while eating peanuts 3 hours ago. He now \
                has a persistent cough and his mother reports hearing a wheeze on \
                the right side. He is not in respiratory distress and oxygen \
                saturations are 97%.
                """,
            keyHistoryPoints: [
                "Witnessed choking episode — timing, onset, what the child was eating or playing with",
                "Type of foreign body — organic (peanut, seed) causes more mucosal reaction than inorganic",
                "Triad: sudden choking, coughing, wheezing (present in ~70% of cases)",
                "Current respiratory status — improving or worsening",
                "Time since aspiration — delayed presentation increases complication risk",
                "Immunisation status (relevant for anaesthetic planning)"
            ],
            examinationFindings: [
                "Unilateral wheeze on the right side (right main bronchus most common site due to anatomy)",
                "Reduced air entry on the affected side",
                "No stridor at rest (laryngeal/tracheal FB would cause stridor)",
                "Respiratory rate normal, no use of accessory muscles, no cyanosis",
                "Oxygen saturations 97% — currently stable",
                "Examine the oropharynx (FB may be visible supraglottically, but do not perform blind finger sweep)"
            ],
            investigations: [
                "Chest X-ray (inspiratory and expiratory or bilateral decubitus in young children): hyperinflation of the affected lung (air trapping due to ball-valve effect), mediastinal shift away from affected side on expiration",
                "Most aspirated foreign bodies (80–90%) are radiolucent (nuts, food) — normal X-ray does not exclude FB",
                "If high clinical suspicion despite normal X-ray: proceed to rigid bronchoscopy",
                "CT chest is rarely needed but may help in delayed presentations with secondary changes"
            ],
            managementPlan: [
                "Rigid bronchoscopy under general anaesthesia — diagnostic and therapeutic (gold standard)",
                "Performed by experienced paediatric ENT surgeon or paediatric bronchoscopist",
                "Anaesthetic considerations: spontaneous ventilation, avoid positive pressure before extraction (may push FB distally)",
                "Use optical forceps or basket to retrieve the foreign body under direct vision",
                "Post-extraction: repeat bronchoscopy to check for residual fragments and assess mucosal damage",
                "Post-operative: chest X-ray, short course of antibiotics if mucosal reaction or delayed presentation",
                "Parental education on choking risks: avoid peanuts, grapes, small toys in children under 3"
            ],
            criticalPoints: [
                "Must maintain a high index of suspicion — a normal X-ray does NOT exclude an inhaled FB",
                "Must proceed to rigid bronchoscopy if clinical history is suggestive, regardless of X-ray findings",
                "Must not attempt blind retrieval with a finger or forceps in the ED",
                "Must be prepared for complete airway obstruction — resuscitation equipment must be immediately available"
            ],
            teachingNotes: """
                Inhaled foreign body is a paediatric emergency with peak incidence \
                at age 1–3 years. Peanuts are the most commonly aspirated FB and \
                are particularly dangerous because they swell with moisture and \
                release arachidonic acid, causing intense mucosal inflammation. The \
                right main bronchus is more commonly affected because it is wider, \
                shorter, and more vertical than the left. A negative chest X-ray \
                with a convincing history still warrants bronchoscopy — the clinical \
                history is the most important diagnostic tool.
                """,
            tags: ["foreign body", "bronchoscopy", "choking", "paediatric airway", "emergency", "peanut"]
        )
    ]
}
