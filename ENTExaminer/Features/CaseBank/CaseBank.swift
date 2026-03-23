import Foundation

// MARK: - ENT Subspecialty

enum ENTSubspecialty: String, Codable, CaseIterable, Sendable {
    case headAndNeck = "Head & Neck"
    case otology = "Otology"
    case rhinology = "Rhinology"
    case pediatricENT = "Pediatric ENT"
    case laryngology = "Laryngology"
    case generalKnowledge = "General Knowledge"
    case infectiousDiseases = "Infectious Diseases"
    case generalSurgery = "General Surgery"
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
        + generalKnowledgeCases
        + infectiousDiseasesCases
        + generalSurgeryCases

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

    // MARK: - General Knowledge Cases

    private static let generalKnowledgeCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "B0000001-0001-0001-0001-000000000001")!,
            title: "World War II",
            subspecialty: .generalKnowledge,
            difficulty: .intermediate,
            clinicalVignette: """
                World War II (1939–1945) was the deadliest and most widespread conflict \
                in human history, involving over 30 countries and resulting in an estimated \
                70–85 million fatalities. The war was fought between the Allied Powers \
                (primarily the United Kingdom, the Soviet Union, the United States, and China) \
                and the Axis Powers (Nazi Germany, Imperial Japan, and Fascist Italy). It \
                reshaped the political, social, and economic landscape of the entire world.
                """,
            keyHistoryPoints: [
                "Germany invaded Poland on 1 September 1939, prompting Britain and France to declare war",
                "The Fall of France in June 1940 left Britain standing alone against Nazi Germany in Western Europe",
                "Operation Barbarossa (June 1941) — Germany's invasion of the Soviet Union opened the vast Eastern Front",
                "The attack on Pearl Harbor (7 December 1941) brought the United States into the war",
                "The Battle of Stalingrad (1942–1943) was a decisive turning point on the Eastern Front",
                "D-Day (6 June 1944) — the Allied invasion of Normandy opened a second front in Western Europe"
            ],
            examinationFindings: [
                "The Battle of Britain (1940) was the first major campaign fought entirely by air forces and prevented a German invasion",
                "The Holocaust resulted in the systematic murder of approximately six million Jewish people and millions of others",
                "The Battle of Midway (June 1942) shifted the balance of naval power in the Pacific to the Allies",
                "The Manhattan Project developed atomic weapons, culminating in the bombings of Hiroshima and Nagasaki in August 1945",
                "The war in Europe ended with Germany's unconditional surrender on 8 May 1945 (VE Day)",
                "Japan surrendered on 15 August 1945 (VJ Day) following the atomic bombings and Soviet declaration of war"
            ],
            investigations: [
                "The war accelerated technological advances including radar, jet engines, rocketry, and nuclear energy",
                "Bletchley Park codebreakers, including Alan Turing, cracked the Enigma machine and shortened the war significantly",
                "Penicillin was mass-produced for the first time to treat wounded soldiers, revolutionising medicine",
                "The Nuremberg Trials (1945–1946) established precedents for prosecuting crimes against humanity",
                "The United Nations was founded in 1945 to prevent future global conflicts"
            ],
            managementPlan: [
                "The Marshall Plan (1948) provided American economic aid to rebuild Western Europe and counter Soviet influence",
                "The war led directly to the Cold War between the United States and the Soviet Union",
                "Decolonisation accelerated as European empires weakened — India, Indonesia, and many African nations gained independence",
                "The Geneva Conventions were updated (1949) to strengthen protections for civilians and prisoners of war",
                "NATO was formed in 1949 as a collective defence alliance against potential Soviet aggression",
                "The European Coal and Steel Community (1951), a forerunner of the EU, aimed to make future European wars impossible"
            ],
            criticalPoints: [
                "The war caused an estimated 70–85 million deaths, making it the deadliest conflict in history",
                "The Holocaust represents one of the most systematic genocides ever perpetrated",
                "The use of atomic weapons on Hiroshima and Nagasaki remains the only use of nuclear weapons in warfare",
                "The war fundamentally redrew national borders across Europe, Asia, and the Middle East",
                "The conflict established the United States and the Soviet Union as the two global superpowers"
            ],
            teachingNotes: """
                Winston Churchill, Franklin D. Roosevelt, and Joseph Stalin — the 'Big Three' — \
                shaped Allied strategy through conferences at Tehran, Yalta, and Potsdam. \
                The war produced enduring cultural touchstones: Churchill's 'We shall fight on the beaches' \
                speech, Rosie the Riveter symbolising women's contribution to industry, and the phrase \
                'Never again' as a response to the Holocaust.
                """,
            tags: ["history", "war", "20th century", "global conflict", "politics"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0002-0001-0001-000000000002")!,
            title: "The Solar System",
            subspecialty: .generalKnowledge,
            difficulty: .straightforward,
            clinicalVignette: """
                Our solar system formed approximately 4.6 billion years ago from a collapsing \
                cloud of gas and dust known as a solar nebula. It consists of a central star \
                (the Sun), eight major planets, dwarf planets, moons, asteroids, comets, and \
                vast amounts of interplanetary dust and gas. The system spans roughly 287 billion \
                kilometres to the edge of the Oort Cloud and is located in the Orion Arm of the \
                Milky Way galaxy.
                """,
            keyHistoryPoints: [
                "The eight planets in order from the Sun: Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune",
                "The inner four planets (Mercury, Venus, Earth, Mars) are rocky terrestrial planets",
                "The outer four planets (Jupiter, Saturn, Uranus, Neptune) are gas and ice giants",
                "Pluto was reclassified as a dwarf planet by the International Astronomical Union in 2006",
                "The asteroid belt lies between Mars and Jupiter, containing millions of rocky bodies",
                "The Kuiper Belt extends beyond Neptune and contains icy bodies including Pluto and Eris"
            ],
            examinationFindings: [
                "The Sun contains 99.86% of all mass in the solar system and is composed primarily of hydrogen and helium",
                "Jupiter is the largest planet — over 1,300 Earths could fit inside it, and its Great Red Spot is a storm larger than Earth",
                "Saturn's ring system is made of billions of particles of ice and rock, spanning up to 282,000 km but only about 10 metres thick",
                "Earth is the only known planet to support liquid water on its surface and harbour life",
                "Venus has a runaway greenhouse effect with surface temperatures of about 465°C, hotter than Mercury despite being further from the Sun",
                "Mars has the tallest volcano in the solar system — Olympus Mons at 21.9 km high, nearly three times the height of Everest"
            ],
            investigations: [
                "Light from the Sun takes approximately 8 minutes and 20 seconds to reach Earth",
                "The Voyager 1 spacecraft, launched in 1977, is the most distant human-made object and has entered interstellar space",
                "Jupiter's moon Europa and Saturn's moon Enceladus have subsurface oceans and are candidates for extraterrestrial life",
                "The gravitational influence of the Sun extends to the Oort Cloud, approximately 1–2 light-years away",
                "Tidal forces from Jupiter prevented the asteroid belt from forming into a planet",
                "The planets all orbit the Sun in roughly the same plane (the ecliptic) due to the original solar nebula's rotation"
            ],
            managementPlan: [
                "NASA's Artemis programme aims to return humans to the Moon and establish a sustained lunar presence",
                "Mars exploration missions (Perseverance rover, Mars Sample Return) are searching for signs of ancient life",
                "The James Webb Space Telescope studies exoplanets and the earliest galaxies, advancing understanding of planetary formation",
                "Planetary defence programmes like DART (Double Asteroid Redirection Test) aim to protect Earth from asteroid impacts",
                "Space agencies are studying the feasibility of crewed missions to Mars, potentially in the 2030s–2040s",
                "International cooperation through the ISS demonstrates how nations can collaborate in space exploration"
            ],
            criticalPoints: [
                "Earth is the only known planet with conditions suitable for liquid water and life as we know it",
                "The Sun will eventually expand into a red giant in about 5 billion years, engulfing the inner planets",
                "Jupiter's massive gravity acts as a cosmic shield, deflecting many asteroids and comets away from the inner solar system",
                "The solar system is approximately 4.6 billion years old, determined by radiometric dating of meteorites",
                "Understanding our solar system is fundamental to the search for habitable exoplanets around other stars"
            ],
            teachingNotes: """
                A handy mnemonic for planet order is 'My Very Educated Mother Just Served Us Nachos.' \
                Saturn is less dense than water — it would float if you could find a bathtub large enough. \
                A day on Venus is longer than its year: Venus takes 243 Earth days to rotate but only \
                225 Earth days to orbit the Sun. Neptune's winds are the fastest in the solar system, \
                reaching speeds of over 2,000 km/h.
                """,
            tags: ["astronomy", "space", "planets", "science", "solar system"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0003-0001-0001-000000000003")!,
            title: "Shakespeare's Major Plays",
            subspecialty: .generalKnowledge,
            difficulty: .intermediate,
            clinicalVignette: """
                William Shakespeare (1564–1616) is widely regarded as the greatest writer in \
                the English language and the world's pre-eminent dramatist. Born in Stratford-upon-Avon, \
                he wrote approximately 37 plays, 154 sonnets, and several longer poems. His works \
                span tragedy, comedy, history, and romance, and have been translated into every \
                major language. His plays continue to be performed more often than those of any \
                other playwright.
                """,
            keyHistoryPoints: [
                "Shakespeare's four great tragedies are Hamlet, Othello, King Lear, and Macbeth",
                "Romeo and Juliet (c.1597) tells of star-crossed lovers from feuding families in Verona",
                "A Midsummer Night's Dream is one of his most popular comedies, blending fairy magic with human love",
                "The Tempest (c.1611) is believed to be the last play Shakespeare wrote alone, featuring the magician Prospero",
                "Henry V depicts the Battle of Agincourt and contains the famous 'Once more unto the breach' speech",
                "The Merchant of Venice raises complex questions about justice, mercy, and prejudice through the character of Shylock"
            ],
            examinationFindings: [
                "Hamlet's 'To be or not to be' soliloquy is perhaps the most famous passage in all of English literature",
                "Macbeth explores ambition, guilt, and the corrupting nature of power — 'Out, damned spot!' is Lady Macbeth's cry of guilt",
                "Othello examines jealousy and manipulation through Iago's scheming against the Moorish general Othello",
                "King Lear deals with ageing, madness, and the consequences of vanity as an elderly king divides his kingdom",
                "The comedies often feature disguise, mistaken identity, and marriages — Much Ado About Nothing and Twelfth Night are prime examples",
                "Shakespeare's history plays (Richard II, Henry IV Parts 1 & 2, Henry V) form a connected tetralogy covering English dynastic conflict"
            ],
            investigations: [
                "Shakespeare coined or popularised over 1,700 words including 'assassination,' 'eyeball,' 'lonely,' and 'generous'",
                "The Globe Theatre, where many of his plays were first performed, was built in 1599 and reconstructed in 1997 near its original site",
                "Scholars debate whether Shakespeare wrote all plays attributed to him — the 'authorship question' has proposed candidates like Marlowe and Bacon",
                "The First Folio (1623), published seven years after Shakespeare's death, preserved 36 of his plays, 18 of which had never been printed",
                "Shakespeare wrote during the Elizabethan and Jacobean eras, when theatre was a popular entertainment for all social classes",
                "His plays reflect contemporary concerns: the divine right of kings, religious conflict, colonialism, and the nature of power"
            ],
            managementPlan: [
                "Shakespeare's works form the foundation of English literature curricula worldwide",
                "Modern adaptations include films (Baz Luhrmann's Romeo + Juliet, Kenneth Branagh's Henry V), musicals (West Side Story), and novels",
                "His plays continue to be reinterpreted through diverse casting, contemporary settings, and cross-cultural productions",
                "The Royal Shakespeare Company in Stratford-upon-Avon remains dedicated to performing and promoting his works",
                "Shakespeare's influence extends to everyday language — phrases like 'break the ice,' 'wild goose chase,' and 'heart of gold' originate from his plays",
                "Understanding Shakespeare develops skills in close reading, rhetorical analysis, and appreciation of dramatic structure"
            ],
            criticalPoints: [
                "Shakespeare wrote approximately 37 plays across four genres: tragedies, comedies, histories, and romances",
                "His works have been in continuous performance for over 400 years and are staged in virtually every country",
                "The First Folio is one of the most important books in English literature — without it, half his plays would have been lost",
                "Shakespeare's exploration of universal human themes — love, jealousy, ambition, mortality — explains his enduring relevance",
                "He is credited with profoundly shaping the English language itself through new words and expressions"
            ],
            teachingNotes: """
                Shakespeare's shortest play is The Comedy of Errors; his longest is Hamlet. \
                All female roles were originally played by boys, as women were not permitted to \
                act on the English stage until 1660. The curse of 'the Scottish play' (Macbeth) is a \
                famous theatrical superstition — actors avoid saying the name in a theatre for fear \
                of bad luck. Shakespeare left his wife Anne Hathaway his 'second-best bed' in his will, \
                which scholars have debated for centuries.
                """,
            tags: ["literature", "theatre", "English", "drama", "poetry"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0004-0001-0001-000000000004")!,
            title: "How the Internet Works",
            subspecialty: .generalKnowledge,
            difficulty: .intermediate,
            clinicalVignette: """
                The Internet is a global network of interconnected computer networks that \
                communicate using standardised protocols. Originating from ARPANET in the late \
                1960s, it has grown to connect billions of devices worldwide. The Internet \
                underpins modern communication, commerce, entertainment, and information access, \
                and its architecture is built on layered protocols that enable diverse applications \
                from email to video streaming to cloud computing.
                """,
            keyHistoryPoints: [
                "ARPANET, funded by the US Department of Defense, sent its first message in 1969 between UCLA and Stanford",
                "TCP/IP (Transmission Control Protocol/Internet Protocol) became the standard networking protocol in 1983",
                "Tim Berners-Lee invented the World Wide Web at CERN in 1989, creating HTML, URLs, and HTTP",
                "The first web browser (Mosaic, 1993) made the Internet accessible to the general public",
                "The dot-com boom of the late 1990s saw explosive growth in Internet-based businesses",
                "Today over 5 billion people use the Internet, roughly 65% of the world's population"
            ],
            examinationFindings: [
                "Data travels as packets — small chunks of information that are independently routed and reassembled at the destination",
                "DNS (Domain Name System) translates human-readable domain names (e.g., google.com) into numerical IP addresses",
                "Routers direct data packets between networks, using routing tables to find the most efficient path",
                "HTTP (HyperText Transfer Protocol) and HTTPS (its encrypted version) govern how web browsers communicate with servers",
                "Undersea fibre-optic cables carry over 95% of international Internet traffic across ocean floors",
                "ISPs (Internet Service Providers) connect individual users and organisations to the broader Internet backbone"
            ],
            investigations: [
                "The Internet uses a layered model: physical, data link, network (IP), transport (TCP/UDP), and application layers",
                "Encryption via TLS/SSL secures data in transit — the padlock icon in browsers indicates an HTTPS connection",
                "BGP (Border Gateway Protocol) manages routing between large autonomous networks that make up the Internet",
                "Content Delivery Networks (CDNs) cache copies of content at geographically distributed servers to reduce latency",
                "IPv4 addresses (e.g., 192.168.1.1) are being replaced by IPv6 due to address exhaustion — IPv6 provides 340 undecillion addresses",
                "Cloud computing (AWS, Azure, Google Cloud) provides on-demand computing resources over the Internet"
            ],
            managementPlan: [
                "Net neutrality principles advocate that ISPs should treat all Internet traffic equally without discrimination",
                "Cybersecurity measures include firewalls, encryption, multi-factor authentication, and regular software updates",
                "Internet governance involves organisations like ICANN (domain names), IETF (technical standards), and W3C (web standards)",
                "Digital literacy education helps people navigate online safely, recognise misinformation, and protect their privacy",
                "The digital divide — unequal access to the Internet — remains a major global challenge, particularly in developing nations",
                "Emerging technologies like 5G, satellite Internet (Starlink), and mesh networks aim to expand global connectivity"
            ],
            criticalPoints: [
                "The Internet and the World Wide Web are not the same thing — the Internet is the infrastructure, the Web is a service that runs on it",
                "DNS is sometimes called 'the phonebook of the Internet' and is essential for translating domain names to IP addresses",
                "Data packets can take different routes across the network and arrive out of order — TCP reassembles them correctly",
                "Over 95% of international data travels through undersea fibre-optic cables, making them critical infrastructure",
                "HTTPS encryption is essential for secure online transactions, passwords, and personal data"
            ],
            teachingNotes: """
                The first ARPANET message was supposed to be 'LOGIN' but the system crashed after \
                transmitting just 'LO', making the first Internet message an unintentionally poetic \
                'Lo' — as in 'Lo and behold.' An estimated 4.9 billion emails are sent every day, \
                though roughly 45% are spam. The Internet weighs about 50 grams — that is the combined \
                mass of all the electrons in motion carrying data at any given moment. A single Google \
                search uses about 0.3 watt-hours of energy.
                """,
            tags: ["technology", "computing", "networks", "digital", "communication"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0005-0001-0001-000000000005")!,
            title: "Climate Change",
            subspecialty: .generalKnowledge,
            difficulty: .challenging,
            clinicalVignette: """
                Climate change refers to long-term shifts in global temperatures and weather \
                patterns. While natural climate variations have occurred throughout Earth's history, \
                since the mid-20th century human activities — primarily the burning of fossil fuels — \
                have been the dominant driver of rapid global warming. The concentration of carbon \
                dioxide in the atmosphere has risen from about 280 ppm before the Industrial Revolution \
                to over 420 ppm today, a level unprecedented in at least 800,000 years.
                """,
            keyHistoryPoints: [
                "The greenhouse effect was first described by Joseph Fourier in the 1820s and experimentally confirmed by John Tyndall in 1859",
                "Svante Arrhenius predicted in 1896 that burning fossil fuels could lead to global warming",
                "Charles David Keeling began continuous CO2 measurements at Mauna Loa in 1958 — the 'Keeling Curve' shows a steady rise",
                "The Intergovernmental Panel on Climate Change (IPCC) was established in 1988 to assess climate science",
                "The Paris Agreement (2015) set the goal of limiting warming to 1.5°C above pre-industrial levels",
                "Global average temperature has already risen approximately 1.1°C above pre-industrial levels as of the 2020s"
            ],
            examinationFindings: [
                "Arctic sea ice has declined by about 13% per decade since satellite records began in 1979",
                "Sea levels have risen approximately 20 cm since 1900 and the rate of rise is accelerating",
                "Extreme weather events — heatwaves, droughts, floods, and intense storms — are increasing in frequency and severity",
                "Coral reefs are experiencing mass bleaching events due to ocean warming; the Great Barrier Reef has had multiple severe events",
                "Permafrost in the Arctic is thawing, releasing stored methane and CO2 — a dangerous positive feedback loop",
                "Ocean acidification (a 30% increase in acidity since pre-industrial times) threatens marine ecosystems and shell-forming organisms"
            ],
            investigations: [
                "Ice cores from Antarctica and Greenland provide a record of atmospheric CO2 and temperature going back 800,000 years",
                "Climate models use physics-based simulations to project future warming under different emission scenarios",
                "The carbon cycle describes how carbon moves between the atmosphere, oceans, soil, and living organisms",
                "The IPCC's Sixth Assessment Report (2021–2023) states that human influence on the climate system is 'unequivocal'",
                "Methane (CH4) is over 80 times more potent than CO2 as a greenhouse gas over a 20-year period",
                "Satellite observations track ice sheet mass loss, sea level rise, and atmospheric greenhouse gas concentrations globally"
            ],
            managementPlan: [
                "Transitioning from fossil fuels to renewable energy sources (solar, wind, hydroelectric, nuclear) is the primary mitigation strategy",
                "Energy efficiency improvements in buildings, transport, and industry can significantly reduce emissions",
                "Carbon capture and storage (CCS) technologies aim to remove CO2 from industrial emissions or directly from the atmosphere",
                "Reforestation and protecting existing forests act as natural carbon sinks, absorbing CO2 from the atmosphere",
                "Adaptation strategies include building sea walls, developing drought-resistant crops, and updating infrastructure for extreme weather",
                "International cooperation through agreements like the Paris Agreement is essential for coordinated global action"
            ],
            criticalPoints: [
                "The scientific consensus is overwhelming: over 97% of climate scientists agree that human activities are causing global warming",
                "Crossing the 1.5°C warming threshold risks triggering irreversible tipping points such as ice sheet collapse and Amazon dieback",
                "Climate change disproportionately affects vulnerable populations and developing nations that have contributed least to emissions",
                "The window for limiting warming to 1.5°C is rapidly closing — substantial emission reductions are needed by 2030",
                "Methane emissions from agriculture, fossil fuel extraction, and thawing permafrost represent a critical and often underestimated threat"
            ],
            teachingNotes: """
                If all of Greenland's ice sheet melted, global sea levels would rise by approximately \
                7 metres. The five warmest years on record have all occurred since 2015. Trees are \
                natural carbon capture machines — a single mature tree absorbs roughly 22 kg of CO2 \
                per year. The term 'greenhouse effect' is somewhat misleading: actual greenhouses work \
                by trapping warm air, while the atmospheric greenhouse effect works by absorbing and \
                re-emitting infrared radiation.
                """,
            tags: ["environment", "science", "climate", "energy", "sustainability"]
        ),

        ClinicalCase(
            id: UUID(uuidString: "B0000001-0006-0001-0001-000000000006")!,
            title: "The Human Body",
            subspecialty: .generalKnowledge,
            difficulty: .straightforward,
            clinicalVignette: """
                The human body is an extraordinarily complex biological system composed of \
                approximately 37 trillion cells organised into tissues, organs, and organ systems. \
                These systems work together to maintain homeostasis — a stable internal environment — \
                despite constantly changing external conditions. Understanding the basics of human \
                anatomy and physiology is fundamental to appreciating how we live, move, think, \
                and heal.
                """,
            keyHistoryPoints: [
                "The skeletal system comprises 206 bones in adults, providing structure, protection, and enabling movement",
                "The heart beats approximately 100,000 times per day, pumping about 7,500 litres of blood through the body",
                "The brain contains roughly 86 billion neurons and consumes about 20% of the body's energy despite being only 2% of body weight",
                "The largest organ is the skin, which covers about 1.7 square metres in an average adult",
                "The small intestine is approximately 6 metres long and is the primary site of nutrient absorption",
                "Humans have 23 pairs of chromosomes containing approximately 20,000–25,000 protein-coding genes"
            ],
            examinationFindings: [
                "The circulatory system consists of the heart, arteries, veins, and capillaries — laid end to end, blood vessels would stretch about 100,000 km",
                "The respiratory system exchanges gases: oxygen is absorbed in the alveoli of the lungs, while carbon dioxide is expelled",
                "The digestive system breaks down food through mechanical and chemical processes, from mouth to large intestine",
                "The immune system defends against pathogens using innate immunity (immediate) and adaptive immunity (specific, memory-based)",
                "The endocrine system uses hormones — chemical messengers — to regulate metabolism, growth, reproduction, and mood",
                "The nervous system is divided into the central nervous system (brain and spinal cord) and peripheral nervous system"
            ],
            investigations: [
                "Red blood cells carry oxygen using haemoglobin and live for approximately 120 days before being recycled in the spleen",
                "The liver performs over 500 functions including detoxification, bile production, and protein synthesis",
                "The kidneys filter approximately 180 litres of blood per day, producing about 1–2 litres of urine",
                "Muscles make up roughly 40% of body weight and are classified as skeletal (voluntary), smooth (involuntary), and cardiac",
                "DNA replication occurs with remarkable accuracy — the error rate is approximately 1 in 10 billion base pairs copied",
                "The gut microbiome contains trillions of microorganisms that aid digestion, produce vitamins, and support immune function"
            ],
            managementPlan: [
                "A balanced diet including proteins, carbohydrates, fats, vitamins, and minerals is essential for optimal body function",
                "Regular physical exercise strengthens the cardiovascular system, builds muscle, improves mental health, and reduces disease risk",
                "Adequate sleep (7–9 hours for adults) is critical for memory consolidation, immune function, and cellular repair",
                "Staying hydrated is vital — the body is approximately 60% water and needs 2–3 litres of fluid intake per day",
                "Vaccination trains the adaptive immune system to recognise and fight specific pathogens before infection occurs",
                "Preventive health measures include regular health screenings, dental care, sun protection, and avoiding tobacco and excessive alcohol"
            ],
            criticalPoints: [
                "The brain can survive only about 4–6 minutes without oxygen before irreversible damage begins",
                "The heart is the only muscle that never rests — it works continuously from before birth until death",
                "Blood types (A, B, AB, O) and the Rh factor are critical for safe blood transfusions",
                "The body maintains core temperature within a narrow range (36.1–37.2°C) — deviation outside this range can be life-threatening",
                "Homeostasis — the body's ability to maintain stable internal conditions — is fundamental to survival"
            ],
            teachingNotes: """
                Stomach acid (hydrochloric acid) has a pH of 1.5–3.5 and is strong enough to dissolve \
                metal — the stomach lining replaces itself every 3–4 days to avoid being digested. \
                The human nose can detect over 1 trillion different scents. Nerve impulses travel at \
                speeds of up to 120 metres per second. If you unravelled all the DNA in a single human \
                cell and stretched it out, it would be about 2 metres long — the total DNA in your body \
                would stretch to the Sun and back about 600 times.
                """,
            tags: ["biology", "anatomy", "health", "science", "medicine"]
        )
    ]

    // MARK: - Infectious Diseases Cases

    private static let infectiousDiseasesCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0001-0001-0001-000000000001")!,
            title: "Community-Acquired Pneumonia",
            subspecialty: .infectiousDiseases,
            difficulty: .straightforward,
            clinicalVignette: """
                A 58-year-old man presents with a 4-day history of productive cough with \
                rust-coloured sputum, fever of 38.9°C, rigors, and right-sided pleuritic \
                chest pain. He is a smoker with no significant past medical history. \
                Examination reveals bronchial breathing and crackles at the right base.
                """,
            keyHistoryPoints: [
                "Duration and onset of symptoms (acute vs subacute)",
                "Character of sputum (rust-coloured suggests pneumococcal)",
                "Smoking history — major risk factor",
                "Vaccination status (pneumococcal, influenza)",
                "Recent travel or hospitalisation",
                "Immunosuppression or comorbidities"
            ],
            examinationFindings: [
                "Fever 38.9°C with tachycardia",
                "Bronchial breathing at right base — consolidation",
                "Increased vocal resonance and dullness to percussion",
                "Reduced oxygen saturations (SpO2 93% on air)",
                "Respiratory rate elevated at 24/min"
            ],
            investigations: [
                "Chest X-ray — lobar consolidation right lower lobe",
                "Blood cultures before antibiotics",
                "Sputum culture and sensitivity",
                "CRP and white cell count (raised neutrophils)",
                "CURB-65 score for severity assessment",
                "Urine pneumococcal and legionella antigens"
            ],
            managementPlan: [
                "CURB-65 score determines setting (community vs hospital vs ICU)",
                "Empirical antibiotics: amoxicillin for mild, co-amoxiclav + macrolide for moderate",
                "Oxygen therapy to maintain SpO2 94-98%",
                "Fluid resuscitation if septic",
                "Repeat CXR at 6 weeks to confirm resolution",
                "Smoking cessation advice"
            ],
            criticalPoints: [
                "Always calculate CURB-65 (Confusion, Urea, RR, BP, age ≥65)",
                "Blood cultures BEFORE starting antibiotics",
                "Consider atypical organisms (Legionella, Mycoplasma) if not responding",
                "Parapneumonic effusion/empyema if not improving"
            ],
            teachingNotes: """
                Streptococcus pneumoniae remains the most common cause of CAP. The CURB-65 \
                score is essential for guiding management — a score of 0-1 can be managed \
                in the community, 2 consider hospital, 3-5 requires hospital and consider ICU.
                """,
            tags: ["pneumonia", "respiratory", "antibiotics", "CURB-65", "sepsis"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0002-0001-0001-000000000002")!,
            title: "Bacterial Meningitis",
            subspecialty: .infectiousDiseases,
            difficulty: .challenging,
            clinicalVignette: """
                A 22-year-old university student presents with a 12-hour history of severe \
                headache, neck stiffness, photophobia, and vomiting. His flatmate reports \
                he has become increasingly confused. Temperature is 39.5°C and a non-blanching \
                petechial rash is noted on his trunk and legs.
                """,
            keyHistoryPoints: [
                "Rapid onset over hours — suggests bacterial rather than viral",
                "Classic triad: headache, neck stiffness, fever",
                "Altered consciousness — indicates severity",
                "Non-blanching rash — meningococcal until proven otherwise",
                "Close contacts (university halls — high-risk setting)",
                "Vaccination history (MenACWY, MenB)"
            ],
            examinationFindings: [
                "GCS 13 (confused, opens eyes to voice)",
                "Marked neck stiffness — positive Kernig's and Brudzinski's signs",
                "Petechial and purpuric rash — non-blanching (glass test)",
                "Photophobia",
                "Tachycardia 120 bpm, BP 95/60 — early septic shock",
                "No focal neurological deficits"
            ],
            investigations: [
                "Blood cultures — BEFORE antibiotics if no delay",
                "Lumbar puncture if no contraindications (raised ICP, coagulopathy, rash)",
                "CSF: high WCC (neutrophils), high protein, low glucose, Gram-negative diplococci",
                "FBC, CRP, lactate, coagulation screen",
                "CT head before LP if GCS <12, focal neurology, or seizures",
                "PCR for Neisseria meningitidis"
            ],
            managementPlan: [
                "DO NOT DELAY antibiotics — IV ceftriaxone immediately",
                "Dexamethasone 0.15mg/kg before or with first antibiotic dose",
                "Aggressive fluid resuscitation for septic shock",
                "ICU referral if haemodynamic instability",
                "Public health notification — close contact prophylaxis (ciprofloxacin)",
                "Monitor for complications: SIADH, seizures, cerebral oedema"
            ],
            criticalPoints: [
                "Non-blanching rash + meningism = give antibiotics IMMEDIATELY, do not wait for LP",
                "Dexamethasone reduces mortality in pneumococcal meningitis",
                "Close contacts need prophylactic antibiotics within 24 hours",
                "CT before LP if signs of raised ICP — but never delay antibiotics for imaging"
            ],
            teachingNotes: """
                Neisseria meningitidis (meningococcus) is the most common cause in young adults. \
                The mortality rate is 10-15% even with treatment. The key teaching point is that \
                antibiotics must never be delayed — in primary care, give IM benzylpenicillin \
                before transfer to hospital.
                """,
            tags: ["meningitis", "meningococcal", "sepsis", "lumbar puncture", "emergency"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0003-0001-0001-000000000003")!,
            title: "Pulmonary Tuberculosis",
            subspecialty: .infectiousDiseases,
            difficulty: .intermediate,
            clinicalVignette: """
                A 35-year-old man originally from South Asia presents with a 3-month history \
                of productive cough, night sweats, weight loss of 8kg, and intermittent \
                haemoptysis. He has been in the UK for 2 years and works as a taxi driver. \
                He has no known HIV or immunosuppression.
                """,
            keyHistoryPoints: [
                "Chronic cough >2 weeks — red flag for TB",
                "Constitutional symptoms: night sweats, weight loss, malaise",
                "Haemoptysis — suggests cavitating disease",
                "Country of origin — high TB prevalence area",
                "Contact history — anyone in household with TB",
                "BCG vaccination status, previous TB treatment"
            ],
            examinationFindings: [
                "Thin, cachectic appearance",
                "Low-grade fever 37.8°C",
                "Crackles and bronchial breathing at left apex",
                "Possible lymphadenopathy (cervical)",
                "Finger clubbing may be present in chronic disease",
                "Check for hepatosplenomegaly (disseminated TB)"
            ],
            investigations: [
                "Chest X-ray — upper lobe cavitation, infiltrates, fibrosis",
                "Sputum for acid-fast bacilli (AFB) — 3 early morning samples",
                "Sputum culture on Löwenstein-Jensen medium (takes 6-8 weeks)",
                "GeneXpert MTB/RIF — rapid PCR, detects rifampicin resistance",
                "HIV test — all TB patients must be tested",
                "Interferon-gamma release assay (IGRA) or Mantoux test"
            ],
            managementPlan: [
                "Standard regimen: RIPE — Rifampicin, Isoniazid, Pyrazinamide, Ethambutol for 2 months",
                "Continuation phase: Rifampicin + Isoniazid for further 4 months (total 6 months)",
                "Directly Observed Therapy (DOT) if adherence concerns",
                "Contact tracing of household and close contacts",
                "Notify public health (TB is notifiable)",
                "Pyridoxine (vitamin B6) supplementation with isoniazid to prevent peripheral neuropathy"
            ],
            criticalPoints: [
                "Always test for HIV in TB patients",
                "Check visual acuity before starting ethambutol (optic neuritis risk)",
                "Monitor LFTs — rifampicin, isoniazid, and pyrazinamide are all hepatotoxic",
                "MDR-TB if resistance to rifampicin and isoniazid — requires specialist management"
            ],
            teachingNotes: """
                TB remains a major global killer — about 10 million new cases annually. The \
                mnemonic RIPE helps remember first-line drugs. Rifampicin turns body fluids \
                orange-red (warn patients about urine and tears). Treatment must be completed \
                in full even when patients feel better — incomplete treatment drives resistance.
                """,
            tags: ["tuberculosis", "TB", "respiratory", "public health", "antibiotics"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0004-0001-0001-000000000004")!,
            title: "Infective Endocarditis",
            subspecialty: .infectiousDiseases,
            difficulty: .challenging,
            clinicalVignette: """
                A 42-year-old intravenous drug user presents with a 3-week history of \
                intermittent fevers, malaise, and progressive breathlessness. He has a \
                history of hepatitis C. Examination reveals a new pansystolic murmur at \
                the left sternal edge, splinter haemorrhages, and Janeway lesions on his palms.
                """,
            keyHistoryPoints: [
                "IV drug use — major risk factor for right-sided endocarditis",
                "Intermittent fevers with rigors — bacteraemia",
                "Progressive breathlessness — valvular regurgitation or septic emboli",
                "Previous dental work or invasive procedures",
                "Pre-existing valvular disease or prosthetic valves",
                "Hepatitis C co-infection common in IVDU"
            ],
            examinationFindings: [
                "New pansystolic murmur — tricuspid regurgitation (IVDU) or mitral",
                "Splinter haemorrhages in nail beds",
                "Janeway lesions (painless erythematous lesions on palms/soles)",
                "Osler's nodes (painful nodules on fingertips) — immune complex deposition",
                "Splenomegaly",
                "Petechiae on conjunctivae and oral mucosa"
            ],
            investigations: [
                "Blood cultures x3 from different sites before antibiotics",
                "Transthoracic echocardiography (TTE) — then TOE if negative but clinical suspicion high",
                "Look for vegetations, abscess, regurgitation",
                "FBC (anaemia of chronic disease, raised WCC), CRP, ESR",
                "Urinalysis — microscopic haematuria (immune complex glomerulonephritis)",
                "Modified Duke criteria for diagnosis (2 major, or 1 major + 3 minor, or 5 minor)"
            ],
            managementPlan: [
                "Prolonged IV antibiotics — typically 4-6 weeks",
                "Empirical: flucloxacillin + gentamicin (native valve), vancomycin + gentamicin (IVDU/prosthetic)",
                "Guided by blood culture sensitivities once available",
                "Surgical referral if: heart failure, uncontrolled infection, large vegetations (>10mm), embolic events",
                "Monitor renal function (gentamicin toxicity)",
                "Dental assessment and source control"
            ],
            criticalPoints: [
                "Never start antibiotics before taking blood cultures (3 sets minimum)",
                "Staphylococcus aureus is commonest in IVDU (usually right-sided, tricuspid)",
                "Streptococcus viridans commonest in native valve (usually left-sided)",
                "Prosthetic valve endocarditis within 60 days = coagulase-negative staph"
            ],
            teachingNotes: """
                The Duke criteria remain the gold standard for diagnosis. Remember the peripheral \
                stigmata: FROM JANE — Fever, Roth spots, Osler's nodes, Murmur (new), Janeway \
                lesions, Anaemia, Nail haemorrhages, Emboli. Mortality is 20-30% even with treatment.
                """,
            tags: ["endocarditis", "cardiology", "IVDU", "bacteraemia", "Duke criteria"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "C0000001-0005-0001-0001-000000000005")!,
            title: "HIV Seroconversion Illness",
            subspecialty: .infectiousDiseases,
            difficulty: .intermediate,
            clinicalVignette: """
                A 28-year-old man presents with a 10-day history of fever, sore throat, \
                diffuse maculopapular rash, myalgia, and cervical lymphadenopathy. He \
                reports unprotected sexual intercourse with a new partner 3 weeks ago. \
                A monospot test for EBV is negative.
                """,
            keyHistoryPoints: [
                "Symptoms 2-4 weeks after exposure — classic seroconversion window",
                "Glandular fever-like illness with negative monospot — think HIV",
                "Unprotected sexual intercourse — risk factor",
                "Rash — occurs in ~70% of acute HIV infections",
                "Ask about oral ulcers, diarrhoea, weight loss",
                "Previous STI screening history"
            ],
            examinationFindings: [
                "Diffuse maculopapular rash — trunk and face predominantly",
                "Generalised lymphadenopathy (cervical, axillary, inguinal)",
                "Pharyngitis with mucosal ulceration",
                "Fever 38.5°C",
                "Oral candidiasis may be present",
                "No hepatosplenomegaly at this stage typically"
            ],
            investigations: [
                "4th-generation HIV test (p24 antigen + HIV antibody) — may be positive",
                "HIV RNA viral load — detectable before antibodies (high in acute infection)",
                "FBC — lymphopenia, atypical lymphocytes",
                "CD4 count — may be transiently low",
                "Full STI screen (syphilis, hepatitis B/C, gonorrhoea, chlamydia)",
                "LFTs — may show transient transaminitis"
            ],
            managementPlan: [
                "Confirm diagnosis with repeat HIV test and viral load",
                "Early referral to HIV specialist — antiretroviral therapy (ART) recommended for all",
                "Start ART as soon as possible — reduces viral reservoir and transmission risk",
                "Preferred regimen: integrase inhibitor-based (e.g. dolutegravir + tenofovir/emtricitabine)",
                "Partner notification and contact tracing",
                "Baseline resistance testing before starting ART"
            ],
            criticalPoints: [
                "A negative antibody test does NOT exclude acute HIV — must test p24 antigen or RNA",
                "Acute HIV has extremely high viral load — highest transmission risk period",
                "Always consider HIV in unexplained glandular fever-like illness with negative monospot",
                "Treatment is now recommended for ALL HIV-positive patients regardless of CD4 count"
            ],
            teachingNotes: """
                Acute HIV seroconversion is missed in up to 70% of cases because it mimics \
                glandular fever. The key clinical pearl: negative monospot + glandular fever \
                symptoms + risk factors = test for HIV. The window period for 4th-gen tests \
                is about 4 weeks. U=U (Undetectable = Untransmittable) is now established — \
                patients on effective ART with undetectable viral load do not transmit sexually.
                """,
            tags: ["HIV", "seroconversion", "STI", "antiretroviral", "sexual health"]
        )
    ]

    // MARK: - General Surgery Cases

    private static let generalSurgeryCases: [ClinicalCase] = [
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0001-0001-0001-000000000001")!,
            title: "Acute Appendicitis",
            subspecialty: .generalSurgery,
            difficulty: .straightforward,
            clinicalVignette: """
                A 19-year-old woman presents with a 24-hour history of central abdominal \
                pain that has migrated to the right iliac fossa. She has anorexia, nausea, \
                and one episode of vomiting. Temperature is 37.8°C. She is tender in the \
                right iliac fossa with guarding on examination.
                """,
            keyHistoryPoints: [
                "Pain migration from periumbilical to RIF — classic visceral to somatic transition",
                "Anorexia is almost always present — its absence should make you question the diagnosis",
                "Nausea/vomiting typically follows pain onset (unlike gastroenteritis where vomiting comes first)",
                "Duration of symptoms — >48 hours raises concern for perforation",
                "Menstrual history and possibility of pregnancy — must exclude ectopic",
                "Previous similar episodes — grumbling appendicitis"
            ],
            examinationFindings: [
                "RIF tenderness maximal at McBurney's point (two-thirds from umbilicus to ASIS)",
                "Guarding and rebound tenderness — peritoneal irritation",
                "Rovsing's sign positive (palpation of LIF causes RIF pain)",
                "Psoas sign (pain on extension of right hip — retrocaecal appendix)",
                "Low-grade fever 37.5–38.5°C",
                "Tachycardia but usually haemodynamically stable"
            ],
            investigations: [
                "FBC — raised WCC with neutrophilia",
                "CRP — elevated, helps track progression",
                "Urinalysis — exclude UTI (may show mild pyuria if inflamed appendix near ureter)",
                "Pregnancy test — mandatory in women of childbearing age",
                "USS abdomen — first-line imaging, especially in women and children",
                "CT abdomen/pelvis — gold standard sensitivity >95%, use if diagnosis uncertain"
            ],
            managementPlan: [
                "Appendicectomy — laparoscopic preferred (less pain, faster recovery, better cosmesis)",
                "IV antibiotics pre-operatively (co-amoxiclav or cefuroxime + metronidazole)",
                "NBM, IV fluids, analgesia",
                "If perforated with abscess — may need percutaneous drainage first, interval appendicectomy later",
                "Histology of specimen — exclude carcinoid or other pathology",
                "Antibiotics alone is an option in uncomplicated cases (but 25-30% recurrence)"
            ],
            criticalPoints: [
                "Always do a pregnancy test in women of childbearing age",
                "Alvarado score (MANTRELS) helps clinical decision-making",
                "Perforation risk increases significantly after 36-48 hours",
                "A normal WCC does not exclude appendicitis"
            ],
            teachingNotes: """
                Appendicitis is the most common surgical emergency. The Alvarado score \
                uses the mnemonic MANTRELS: Migration of pain, Anorexia, Nausea/vomiting, \
                Tenderness in RIF, Rebound, Elevation of temperature, Leukocytosis, Shift \
                to left (neutrophilia). A score ≥7 strongly suggests appendicitis.
                """,
            tags: ["appendicitis", "acute abdomen", "surgery", "laparoscopy", "emergency"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0002-0001-0001-000000000002")!,
            title: "Small Bowel Obstruction",
            subspecialty: .generalSurgery,
            difficulty: .intermediate,
            clinicalVignette: """
                A 72-year-old woman presents with a 2-day history of colicky abdominal \
                pain, absolute constipation (no flatus or faeces), progressive abdominal \
                distension, and bilious vomiting. She has a midline laparotomy scar from \
                a hysterectomy 15 years ago.
                """,
            keyHistoryPoints: [
                "Classic tetrad: colicky pain, vomiting, distension, absolute constipation",
                "Previous abdominal surgery — adhesions are the commonest cause (60-75%)",
                "Bilious vomiting — suggests proximal obstruction",
                "Absolute constipation (no flatus) — suggests complete obstruction",
                "Duration and progression — worsening distension concerning for closed loop",
                "History of hernias, malignancy, inflammatory bowel disease"
            ],
            examinationFindings: [
                "Abdominal distension — may be marked",
                "High-pitched tinkling bowel sounds — classically described",
                "Diffuse tenderness but no peritonism initially",
                "Check all hernial orifices (inguinal, femoral, incisional) — easily missed cause",
                "Dehydration — dry mucous membranes, tachycardia, reduced urine output",
                "If peritonism develops — suggests strangulation or perforation"
            ],
            investigations: [
                "Abdominal X-ray — dilated small bowel loops >3cm, valvulae conniventes visible across full width",
                "CT abdomen with contrast — gold standard, shows transition point, cause, and complications",
                "Bloods: FBC, U&E (dehydration, hypokalaemia), lactate (strangulation), amylase",
                "VBG — metabolic alkalosis from vomiting, or acidosis if strangulated",
                "Group and save — in case surgery needed",
                "Erect CXR — to exclude perforation (free air under diaphragm)"
            ],
            managementPlan: [
                "Drip and suck: IV fluids (aggressive resuscitation) + NG tube decompression",
                "Catheterise and monitor fluid balance strictly",
                "Correct electrolyte abnormalities (especially K+ and Na+)",
                "Conservative management trial for 24-48 hours if adhesional and no signs of strangulation",
                "Water-soluble contrast (Gastrografin) — both diagnostic and therapeutic in adhesional SBO",
                "Surgery if: strangulation suspected, closed loop, failure to resolve in 48-72 hours, or hernia"
            ],
            criticalPoints: [
                "ALWAYS examine hernial orifices — an obstructed/strangulated hernia needs emergency surgery",
                "Rising lactate, peritonism, or fever suggests strangulation — urgent surgery needed",
                "Distinguish small bowel (central, valvulae conniventes) from large bowel (peripheral, haustra) on X-ray",
                "Never give Gastrografin if perforation suspected"
            ],
            teachingNotes: """
                The rule of 3s for bowel diameters on X-ray: small bowel >3cm, large bowel >6cm, \
                caecum >9cm is abnormal. Adhesional small bowel obstruction accounts for about \
                60-75% of cases. Gastrografin follow-through at 24h is both diagnostic (if contrast \
                reaches colon, likely to resolve) and therapeutic (hyperosmolar, draws fluid into lumen).
                """,
            tags: ["bowel obstruction", "adhesions", "acute abdomen", "surgery", "emergency"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0003-0001-0001-000000000003")!,
            title: "Perforated Duodenal Ulcer",
            subspecialty: .generalSurgery,
            difficulty: .intermediate,
            clinicalVignette: """
                A 55-year-old man presents with sudden-onset severe epigastric pain that \
                began 6 hours ago while at work. The pain rapidly became generalised across \
                the abdomen. He takes regular NSAIDs for back pain and smokes 20 cigarettes \
                per day. He is lying very still, tachycardic at 110 bpm, and the abdomen \
                is rigid on examination.
                """,
            keyHistoryPoints: [
                "Sudden-onset severe epigastric pain — 'thunderclap' presentation",
                "Pain rapidly generalising — peritoneal contamination",
                "NSAID use — major risk factor for peptic ulcer disease",
                "Smoking — impairs mucosal healing",
                "Previous dyspepsia or known ulcer disease",
                "Helicobacter pylori status if known"
            ],
            examinationFindings: [
                "Patient lying very still — movement worsens peritoneal pain",
                "Board-like rigidity — generalised peritonitis",
                "Absent bowel sounds — paralytic ileus from peritonitis",
                "Tachycardia, hypotension — third-space fluid losses and sepsis",
                "Percussion tenderness throughout",
                "Loss of liver dullness — suggests free intraperitoneal gas"
            ],
            investigations: [
                "Erect CXR — free gas under diaphragm (pneumoperitoneum) in 75% of cases",
                "CT abdomen — most sensitive for free gas and fluid, shows site of perforation",
                "Bloods: FBC, U&E, amylase (may be mildly raised), lactate, CRP",
                "VBG — assess acid-base status",
                "Group and save / crossmatch",
                "ECG — to exclude MI (epigastric pain differential)"
            ],
            managementPlan: [
                "Emergency laparotomy or laparoscopic repair",
                "Omental patch repair (Graham patch) — standard technique",
                "Aggressive IV fluid resuscitation pre-operatively",
                "IV PPI (high-dose omeprazole infusion)",
                "Broad-spectrum antibiotics (peritoneal contamination)",
                "Post-operatively: H. pylori eradication, stop NSAIDs, PPI long-term"
            ],
            criticalPoints: [
                "Board-like rigidity + free air = perforation until proven otherwise — do not delay surgery",
                "Absent free air on CXR does NOT exclude perforation (25% have no free air)",
                "Always check amylase — pancreatitis is a key differential",
                "Elderly and immunosuppressed patients may have minimal signs despite serious pathology"
            ],
            teachingNotes: """
                Perforated peptic ulcer is the second most common cause of emergency laparotomy \
                after appendicitis. The classic CXR finding of air under the diaphragm is present \
                in only 75% of cases — CT is much more sensitive. The differential for sudden \
                severe epigastric pain includes pancreatitis, MI, AAA rupture, and mesenteric ischaemia.
                """,
            tags: ["perforation", "peptic ulcer", "peritonitis", "acute abdomen", "emergency surgery"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0004-0001-0001-000000000004")!,
            title: "Acute Cholecystitis",
            subspecialty: .generalSurgery,
            difficulty: .straightforward,
            clinicalVignette: """
                A 45-year-old woman presents with a 3-day history of constant right upper \
                quadrant pain radiating to the right shoulder tip. She has fever of 38.2°C, \
                nausea, and has vomited twice. She describes previous episodes of intermittent \
                RUQ pain after fatty meals that resolved spontaneously. She has a BMI of 34.
                """,
            keyHistoryPoints: [
                "Constant RUQ pain (not colicky) — distinguishes cholecystitis from biliary colic",
                "Radiation to right shoulder tip — diaphragmatic irritation (phrenic nerve C3-5)",
                "Previous episodes of biliary colic — suggests gallstones predating this",
                "Fatty food trigger — fat stimulates CCK, gallbladder contraction",
                "Risk factors: Female, Forty, Fat, Fertile, Fair (the 5 Fs — though not all are evidence-based)",
                "Duration >6 hours distinguishes cholecystitis from biliary colic"
            ],
            examinationFindings: [
                "Murphy's sign positive — inspiratory arrest on palpation of RUQ",
                "RUQ tenderness with guarding",
                "Low-grade fever 38-38.5°C",
                "Palpable gallbladder in some cases (usually not palpable if chronically fibrosed)",
                "Mild jaundice — suspect CBD stone (Mirizzi syndrome or choledocholithiasis)",
                "Check for signs of peritonism — suggests perforation or gangrenous cholecystitis"
            ],
            investigations: [
                "USS abdomen — first-line: gallstones, thickened gallbladder wall >3mm, pericholecystic fluid",
                "Bloods: FBC (raised WCC), CRP, LFTs (ALP/GGT may be raised), amylase",
                "If jaundiced: bilirubin, MRCP to assess CBD for stones",
                "Blood cultures if septic",
                "HIDA scan if diagnosis uncertain (non-filling gallbladder confirms cystic duct obstruction)",
                "ECG — RUQ pain differential includes inferior MI"
            ],
            managementPlan: [
                "IV antibiotics (co-amoxiclav or cefuroxime + metronidazole)",
                "IV fluids, NBM, analgesia (NSAIDs + opioids)",
                "Early laparoscopic cholecystectomy — within 72 hours ('hot cholecystectomy') is now recommended",
                "If unfit for surgery: percutaneous cholecystostomy drainage",
                "Intraoperative cholangiogram if CBD stones suspected",
                "ERCP pre-operatively if confirmed CBD stone with jaundice"
            ],
            criticalPoints: [
                "Murphy's sign is the most useful clinical sign — sensitivity ~65%",
                "Distinguish from ascending cholangitis (Charcot's triad: RUQ pain, jaundice, fever)",
                "Reynolds' pentad adds confusion and hypotension — life-threatening cholangitis",
                "Gallstone ileus — rare but important: air in biliary tree + SBO on X-ray"
            ],
            teachingNotes: """
                The trend has shifted towards early ('hot') cholecystectomy within 72 hours \
                rather than waiting 6 weeks ('cold'). Multiple RCTs show early surgery is safe, \
                reduces total hospital stay, and avoids the 20% readmission rate while waiting. \
                Courvoisier's law: a palpable gallbladder with painless jaundice is unlikely to \
                be gallstones — think pancreatic head malignancy.
                """,
            tags: ["cholecystitis", "gallstones", "biliary", "surgery", "Murphy's sign"]
        ),
        ClinicalCase(
            id: UUID(uuidString: "D0000001-0005-0001-0001-000000000005")!,
            title: "Strangulated Inguinal Hernia",
            subspecialty: .generalSurgery,
            difficulty: .challenging,
            clinicalVignette: """
                A 68-year-old man presents to A&E with a 12-hour history of severe pain \
                in the right groin and a tense, tender lump that he cannot push back. He \
                has known about a reducible right inguinal hernia for 2 years but declined \
                elective repair. He has been vomiting and has not passed flatus for 8 hours. \
                The lump is erythematous and exquisitely tender.
                """,
            keyHistoryPoints: [
                "Previously reducible hernia now irreducible — incarceration",
                "Severe pain, erythema, tenderness — suggests strangulation (vascular compromise)",
                "Vomiting and absent flatus — obstructed bowel within the hernia",
                "Duration of irreducibility — >6 hours with pain = likely strangulation",
                "Previous hernia repair — recurrence is possible",
                "Bilateral hernias — check both sides"
            ],
            examinationFindings: [
                "Tense, tender, irreducible lump in right groin — above and medial to pubic tubercle (inguinal)",
                "Erythematous overlying skin — suggests strangulation",
                "No cough impulse — contents trapped",
                "Absent bowel sounds or tinkling sounds — obstruction",
                "Abdominal distension if prolonged obstruction",
                "Signs of systemic sepsis: tachycardia, fever, hypotension if bowel necrosis"
            ],
            investigations: [
                "Clinical diagnosis — do not delay surgery for investigations",
                "Bloods: FBC, U&E, lactate (raised = ischaemic bowel), VBG",
                "Group and crossmatch — in case bowel resection needed",
                "Abdominal X-ray — may show dilated loops of bowel",
                "CT if diagnosis uncertain — shows hernia contents, bowel wall thickening",
                "ECG and chest X-ray — pre-operative assessment"
            ],
            managementPlan: [
                "EMERGENCY surgery — do not delay (bowel viability at risk)",
                "Adequate resuscitation: IV fluids, NG tube if obstructed, catheter",
                "One gentle attempt at reduction may be tried (Taxis) — but NOT if strangulation suspected",
                "Open or laparoscopic hernia repair — inspect bowel viability",
                "If bowel non-viable: segmental resection with primary anastomosis",
                "Mesh repair if no bowel contamination; tissue repair (Shouldice/Bassini) if contaminated field"
            ],
            criticalPoints: [
                "A strangulated hernia is a SURGICAL EMERGENCY — bowel necrosis occurs within 6 hours",
                "Do NOT attempt to reduce if signs of strangulation (risk of reducing dead bowel into abdomen)",
                "Always distinguish inguinal from femoral hernias — femoral hernias have higher strangulation risk",
                "Femoral hernia: below and lateral to pubic tubercle; inguinal: above and medial"
            ],
            teachingNotes: """
                The key distinction is: incarcerated (irreducible but viable) vs strangulated \
                (irreducible with vascular compromise). Femoral hernias are much more likely to \
                strangulate than inguinal (40% vs 3%). All femoral hernias should be repaired \
                when diagnosed. The Richter's hernia is a dangerous variant where only part of \
                the bowel wall is trapped — it can strangulate without causing obstruction.
                """,
            tags: ["hernia", "strangulation", "emergency surgery", "bowel obstruction", "groin"]
        )
    ]
}
