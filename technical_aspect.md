# Technical Aspect — Création des Operational_Task__c
> Explication technique complète du cycle de création des tâches opérationnelles, du début à la fin, avec toutes les conditions.

---

## Table des matières
1. [Vue d'ensemble des 4 mécanismes](#1-vue-densemble-des-4-mécanismes)
2. [Mécanisme 1 — Création automatique initiale](#2-mécanisme-1--création-automatique-initiale)
3. [Mécanisme 2 — Création sur email entrant](#3-mécanisme-2--création-sur-email-entrant)
4. [Mécanisme 3 — Création par chaînage (outcome)](#4-mécanisme-3--création-par-chaînage-outcome)
5. [Mécanisme 4 — Création manuelle](#5-mécanisme-4--création-manuelle)
6. [Tableau comparatif des 4 mécanismes](#6-tableau-comparatif-des-4-mécanismes)

---

## 1. Vue d'ensemble des 4 mécanismes

```
┌─────────────────────────────────────────────────────────────────────┐
│  MÉCANISME 1                                                        │
│  Flow_Task_Workflow_FirstTask_Creation                              │
│  Déclenché sur : Case (After Save)                                  │
│  → Crée les premières tâches selon le type de Case                  │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│  MÉCANISME 2                                                        │
│  Flow_Task_Creation_on_New_Email_received                           │
│  Déclenché sur : EmailMessage (After Save)                          │
│  → Crée une tâche "Lire email" à chaque email entrant               │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│  MÉCANISME 3                                                        │
│  Flow_Task_Management_Close_Operational_Task                        │
│  Déclenché par : agent qui ferme une tâche                          │
│  → Crée les tâches suivantes selon l'outcome sélectionné            │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│  MÉCANISME 4                                                        │
│  Flow_Task_Management_Create_Manual_Task                            │
│  Déclenché par : agent qui clique "Create Task"                     │
│  → Crée une tâche ad hoc sans modèle                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Mécanisme 1 — Création automatique initiale

**Flow :** `Flow_Task_Workflow_FirstTask_Creation`
**Type :** Record-Triggered Flow — After Save sur `Case`

---

### Condition d'entrée (Entry Criteria)

Le flow ne se déclenche que si **les deux conditions** sont vraies :

```
Condition 1 — RecordType éligible :
  Case.RecordType.Name est dans le Custom Label
  "Task_Management_Enabled_Countries_RecordTypes"

Condition 2 — Au moins un champ pertinent a changé (filterFormula) :
  AND(
    [Condition 1],
    OR(
      ISNEW(),
      ISCHANGED(External_Case_Category__c),
      ISCHANGED(External_Case_Detail__c),
      ISCHANGED(Type),
      ISCHANGED(External_Case_Type__c),
      ISCHANGED(OwnerId),
      ISPICKVAL(Status, "Closed")
    )
  )
```

---

### Chemin A — Case créé ou requalifié → Création des premières tâches

```
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1 — Recherche du Workflow__c (cascade 3 niveaux)              │
│                                                                     │
│  Niveau 1 (le plus précis) :                                        │
│    WHERE Subsidiary_Indicator__c = Case.Subsidiary_Indicator__c     │
│      AND (Type__c = Case.Type                                       │
│           OR Type__c = Case.External_Case_Type__c)                  │
│      AND Category__c = Case.External_Case_Category__c              │
│      AND Details__c  = Case.External_Case_Detail__c                │
│                                                                     │
│  Niveau 2 (si niveau 1 = null) :                                    │
│    WHERE Subsidiary_Indicator__c = Case.Subsidiary_Indicator__c     │
│      AND (Type__c = Case.Type                                       │
│           OR Type__c = Case.External_Case_Type__c)                  │
│      AND Category__c = Case.External_Case_Category__c              │
│      AND Details__c  = null                                         │
│                                                                     │
│  Niveau 3 (si niveau 2 = null) :                                    │
│    WHERE Subsidiary_Indicator__c = Case.Subsidiary_Indicator__c     │
│      AND (Type__c = Case.Type                                       │
│           OR Type__c = Case.External_Case_Type__c)                  │
│      AND Category__c = null                                         │
│      AND Details__c  = null                                         │
│                                                                     │
│  ⚠️ Si aucun niveau ne trouve un Workflow → FIN, rien créé          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2 — Récupération des tâches initiales                         │
│                                                                     │
│  SELECT Id, Task_Subject__c, Task_SLA__c, Default_queue_ID__c,      │
│         Must_be_closed_before_case_can_be_closed__c,                │
│         Only_Available_For_Task_Owners__c,                          │
│         Don_t_Restrict_Assignment__c,                               │
│         Reassign_Task_when_Case_owner_Change__c                     │
│  FROM Workflow_Task__c                                              │
│  WHERE Parent_Workflow__c = [ID Workflow trouvé]                    │
│    AND Is_First_Task__c = true                                      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3 — Transform : Workflow_Task__c → Operational_Task__c        │
│                                                                     │
│  Champ Operational_Task__c          Source                          │
│  ──────────────────────────────────────────────────────            │
│  Name                           ← Workflow_Task__c.Task_Subject__c  │
│  Case__c                        ← Case.Id                           │
│  Workflow_Task__c               ← Workflow_Task__c.Id               │
│  Automatic_Task__c              ← true (valeur fixe)               │
│  OwnerId                        ← Workflow_Task__c.Default_queue_   │
│                                   ID__c                             │
│  Start_Date__c                  ← $Flow.CurrentDateTime             │
│  Task_SLA__c                    ← Workflow_Task__c.Task_SLA__c      │
│  Subsidiary_Indicator__c        ← Case.Subsidiary_Indicator__c      │
│  Subsidiary__c                  ← Case.Subsidiary__c               │
│  Must_be_closed_before_case...  ← Workflow_Task__c.[même champ]    │
│  Only_Available_For_Task_Owners ← Workflow_Task__c.[même champ]    │
│  Don_t_Restrict_Assignment__c   ← Workflow_Task__c.[même champ]    │
│  Reassign_Task_when_Case_owner  ← Workflow_Task__c.[même champ]    │
│  Due_Date__c                    ← calculé à l'étape 4              │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 4 — Calcul de la Due_Date__c via Apex                         │
│                                                                     │
│  Action Apex : profFlow_bhAdd__addBusinessHours                     │
│                                                                     │
│  Input  businessHoursId      = Workflow__c.Business_Hours__c        │
│  Input  startDateTime        = Start_Date__c                        │
│  Input  intervalMilliseconds = Task_SLA__c × 3 600 000              │
│  Output Due_Date__c          = date/heure en heures ouvrées         │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5 — CREATE Operational_Task__c                                │
│  Toute la collection créée en un seul DML                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Chemin B — Case fermé → Fermeture de toutes les tâches ouvertes

```
REQUÊTE :
  SELECT Id FROM Operational_Task__c
  WHERE Case__c = Case.Id
    AND Completion_Date__c = null

BOUCLE sur chaque tâche :
  Completion_Date__c ← $Flow.CurrentDateTime

UPDATE toutes les tâches (un seul DML)
```

---

### Chemin C — Propriétaire du Case changé → Réassignation

```
UPDATE Operational_Task__c :
  WHERE Case__c = Case.Id
    AND Automatic_Task__c = true
    AND Completion_Date__c = null
    AND Reassign_Task_when_Case_owner_Change__c = true
  SET OwnerId = Case.OwnerId
```

---

### Chemin D — Requalification du Case → Annulation des tâches en cours

```
UPDATE Operational_Task__c :
  WHERE Case__c = Case.Id
    AND Automatic_Task__c = true
    AND Completion_Date__c = null
  SET Task_Outcome__c   = "Canceled due to case re-qualification"
      Completion_Date__c = $Flow.CurrentDateTime
```

---

## 3. Mécanisme 2 — Création sur email entrant

**Flow :** `Flow_Task_Creation_on_New_Email_received`
**Type :** Record-Triggered Flow — After Save sur `EmailMessage` (création uniquement)

---

### Condition d'entrée

```
EmailMessage.ParentId IS NOT NULL      ← lié à un Case
AND EmailMessage.Incoming = true       ← email entrant seulement
AND triggerType = RecordAfterSave (création uniquement)
```

### Condition d'éligibilité du Case parent

```
Case.RecordType.Name dans Custom Label
"Task_Management_Enabled_Countries_RecordTypes"
```

---

### Chemin A — Case ouvert

```
┌─────────────────────────────────────────────────────────────────────┐
│ DÉCISION : IS_Case_Closed ?                                         │
│   Case.Status = "Reopened" → aller au Chemin B                     │
│   Sinon → continuer Chemin A                                        │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ COMPTER les emails entrants sur le Case :                           │
│   SELECT COUNT() FROM EmailMessage                                  │
│   WHERE ParentId = Case.Id AND Incoming = true                      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ DÉCISION : 1er email ou email suivant ?                             │
│                                                                     │
│  COUNT = 1 (1er email) :                                            │
│    Si Case.Type = null ET Case.External_Case_Type__c = null         │
│      → FIN (Case non qualifié, pas de tâche)                        │
│    Sinon → continuer vers la création                               │
│                                                                     │
│  COUNT > 1 (email suivant) :                                        │
│    → vérifier l'idempotence (ci-dessous)                            │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ VÉRIFICATION IDEMPOTENCE :                                          │
│   SELECT Id FROM Operational_Task__c                                │
│   WHERE Case__c = Case.Id                                           │
│     AND Completion_Date__c = null                                   │
│     AND Workflow_Task__r.Task_Subject__c = [sujet tâche email]      │
│                                                                     │
│   Si une tâche ouverte existe déjà → FIN (pas de doublon)          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ RECHERCHE Workflow__c "Read Email" :                                 │
│   WHERE Type__c CONTAINS "Read Email"                               │
│     AND Type__c NOT CONTAINS "Closed Case"                          │
│     AND Subsidiary_Indicator__c = Case.Subsidiary_Indicator__c      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
  Workflow_Task__c (Is_First_Task__c = true)
→ APEX calcul SLA
→ CREATE Operational_Task__c
```

---

### Chemin B — Case rouvert (Status = "Reopened")

```
┌─────────────────────────────────────────────────────────────────────┐
│ VÉRIFICATION IDEMPOTENCE :                                          │
│   Tâche "Case Reopening / New Email" ouverte existe ? → FIN         │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ RECHERCHE Workflow__c "Read Email - Closed Case" :                   │
│   WHERE Type__c CONTAINS "Read Email"                               │
│     AND Type__c CONTAINS "Closed Case"                              │
│     AND Subsidiary_Indicator__c = Case.Subsidiary_Indicator__c      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
  Workflow_Task__c (Is_First_Task__c = true)
→ APEX calcul SLA
→ CREATE Operational_Task__c
→ UPDATE Case : Status = "Reopened"
```

---

## 4. Mécanisme 3 — Création par chaînage (outcome)

**Flow :** `Flow_Task_Management_Close_Operational_Task`
**Type :** Screen Flow — lancé depuis le bouton "Close Task" sur Display_Progress

---

### Conditions d'accès au flow (depuis Display_Progress)

```
firstSelectedRow.Id IS NOT NULL            ← tâche sélectionnée
AND firstSelectedRow.Status__c != "Completed"  ← non fermée
AND Allowed_To_Modify = true               ← utilisateur autorisé
```

---

### Logique complète

```
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1 — La tâche a-t-elle un Workflow_Task__c associé ?           │
│                                                                     │
│  Operational_Task__c.Workflow_Task__c IS NOT NULL ?                 │
│    Non → fermer la tâche directement (aller à l'étape 6)           │
│    Oui → continuer                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2 — Récupération des outcomes possibles                       │
│                                                                     │
│  SELECT Id, Label__c, Order__c, Outcome_will_close_Case__c,         │
│         Update_Case_Status__c, Update_Workflow_Step__c,             │
│         Update_Case_Reopening_Reason__c                             │
│  FROM Task_Outcome__c                                               │
│  WHERE From_Task__c = Operational_Task__c.Workflow_Task__c          │
│  ORDER BY Order__c ASC                                              │
│                                                                     │
│  Aucun outcome → fermer directement (aller à l'étape 6)            │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3 — Écran de sélection de l'outcome                           │
│  L'agent choisit un outcome dans la liste                           │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 4 — L'outcome ferme-t-il le Case ?                            │
│                                                                     │
│  Outcome.Outcome_will_close_Case__c = true ?                        │
│    Oui → vérifier les tâches bloquantes :                           │
│           SELECT Id FROM Operational_Task__c                        │
│           WHERE Case__c = Case.Id                                   │
│             AND Completion_Date__c = null                           │
│             AND Must_be_closed_before_case_can_be_closed__c = true  │
│             AND Id != [tâche courante]                              │
│                                                                     │
│           Si tâches bloquantes trouvées                             │
│             → BLOQUER : afficher écran d'erreur, FIN                │
│           Sinon → continuer                                         │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5 — Création des tâches suivantes                             │
│                                                                     │
│  SELECT Workflow_Task__c                                            │
│  FROM Outcome_to_WF_Tasks__c                                        │
│  WHERE Outcome__c = [outcome sélectionné]                           │
│                                                                     │
│  Aucun lien → pas de nouvelle tâche créée                           │
│  N liens → récupérer les N Workflow_Task__c cibles                  │
│                                                                     │
│  SELECT Id, Task_Subject__c, Task_SLA__c, ...                       │
│  FROM Workflow_Task__c                                              │
│  WHERE Id IN [liste des IDs]                                        │
│                                                                     │
│  TRANSFORM + APEX calcul SLA (même logique que mécanisme 1)         │
│  CREATE Operational_Task__c (toutes en un seul DML)                 │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5bis — Mise à jour optionnelle du Case                        │
│                                                                     │
│  Si Outcome.Update_Case_Status__c IS NOT NULL                       │
│    → Case.Status = Outcome.Update_Case_Status__c                    │
│  Si Outcome.Update_Workflow_Step__c IS NOT NULL                     │
│    → Case.Workflow_Step__c = Outcome.Update_Workflow_Step__c        │
│  Si Outcome.Update_Case_Reopening_Reason__c IS NOT NULL             │
│    → Case.Reopening_Reason__c = Outcome.Update_Case_Reopening_      │
│      Reason__c                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 6 — Fermeture de la tâche courante                            │
│                                                                     │
│  UPDATE Operational_Task__c :                                       │
│    Completion_Date__c ← $Flow.CurrentDateTime                       │
│    Closed_by__c       ← $User.FullName                              │
│    Task_Outcome__c    ← Outcome.Label__c                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Mécanisme 4 — Création manuelle

**Flow :** `Flow_Task_Management_Create_Manual_Task`
**Type :** Screen Flow — lancé depuis le bouton "Create Task" sur Display_Progress

---

### Condition d'accès

```
firstSelectedRow.Id IS NOT NULL
(pas de condition de droits — accessible à tous les utilisateurs)
```

---

### Logique

```
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1 — Récupération du contexte                                  │
│   GET Case (via recordId)                                           │
│   GET Queues filtrées par Subsidiary_Indicator__c (code ISO)        │
│   GET Users actifs de la même filiale                               │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2 — Écran de saisie                                           │
│   Task Subject     (champ texte — obligatoire)                      │
│   Start Date       (DateTime — obligatoire)                         │
│   Due Date         (DateTime — obligatoire)                         │
│   Assigned to      Queue OU User (filtré par pays)                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3 — CREATE Operational_Task__c                                │
│                                                                     │
│  Champ                                    Valeur                   │
│  ──────────────────────────────────────────────────────            │
│  Name                                 ← saisie agent               │
│  Case__c                              ← Case.Id                     │
│  Workflow_Task__c                     ← null (pas de modèle)        │
│  Automatic_Task__c                    ← false                       │
│  Only_Available_For_Task_Owners__c    ← true                        │
│  Reassign_Task_when_Case_owner_Change ← false                       │
│  Start_Date__c                        ← saisie agent               │
│  Due_Date__c                          ← saisie agent               │
│  OwnerId                              ← Queue ou User sélectionné   │
│  Subsidiary_Indicator__c              ← Case.Subsidiary_Indicator__c│
│                                                                     │
│  ⚠️ Pas de calcul SLA Apex — la Due Date est saisie manuellement   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. Tableau comparatif des 4 mécanismes

| | Mécanisme 1 | Mécanisme 2 | Mécanisme 3 | Mécanisme 4 |
|---|---|---|---|---|
| **Flow** | FirstTask_Creation | New_Email_received | Close_Operational_Task | Create_Manual_Task |
| **Déclencheur** | Case sauvegardé | Email entrant | Agent ferme une tâche | Agent clique bouton |
| **Type de flow** | Record-Triggered | Record-Triggered | Screen Flow | Screen Flow |
| **`Automatic_Task__c`** | `true` | `true` | `true` | `false` |
| **`Workflow_Task__c`** | ID du modèle | ID du modèle | ID du modèle | `null` |
| **Due Date** | Apex (heures ouvrées) | Apex (heures ouvrées) | Apex (heures ouvrées) | Saisie manuelle |
| **Idempotence** | Non (requalification annule et recrée) | Oui (vérifie doublon) | Non applicable | Non applicable |
| **Peut créer plusieurs tâches** | Oui (N `Is_First_Task`) | Non (1 tâche) | Oui (N outcomes liés) | Non (1 tâche) |
| **Met à jour le Case** | Non | Oui (Reopened) | Oui (selon outcome) | Non |
| **Condition de droits** | Aucune (automatique) | Aucune (automatique) | `Allowed_To_Modify = true` | Aucune |
