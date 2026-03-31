# learningSF — Guide d'apprentissage Salesforce
> Fichier évolutif : chaque concept rencontré dans le projet est expliqué avec un mini-tutoriel.

---

## Table des matières
1. [Les types de Flows Salesforce](#1-les-types-de-flows-salesforce)
2. [Les objets clés du système de tâches](#2-les-objets-clés-du-système-de-tâches)
3. [Documentation : Système Flow_Task_Management](#3-documentation--système-flow_task_management)
4. [Carte des dépendances entre flows](#4-carte-des-dépendances-entre-flows)
5. [Concepts avancés rencontrés](#5-concepts-avancés-rencontrés)

---

## 1. Les types de Flows Salesforce

### 📘 Concept : Qu'est-ce qu'un Flow ?
Un **Flow** est un outil d'automatisation Salesforce qui permet de créer de la logique sans (ou avec peu de) code. Il peut interroger des données, les modifier, afficher des écrans à l'utilisateur, et appeler d'autres automatisations.

Il existe plusieurs types de flows. Voici ceux que tu rencontres dans ce projet :

---

### 🔹 Screen Flow (`processType: Flow`)
**Ce que c'est :** Un flow interactif avec des écrans que l'utilisateur voit et remplit.

**Analogie :** C'est comme un formulaire ou un wizard en plusieurs étapes. L'utilisateur clique, sélectionne, valide.

**Comment il se lance :** Depuis un bouton sur une page d'enregistrement, une Quick Action, ou un composant LWC sur la page.

**Dans ce projet :**
- `Flow_Task_Management_Create_Manual_Task` → formulaire de création d'une tâche
- `Flow_Task_Management_Assign_Task_to_another_User` → sélection d'un assignataire
- `Flow_Task_Management_Display_Progress` → tableau de bord des tâches affiché sur la page Case

---

### 🔹 Record-Triggered Flow — After Save (`triggerType: RecordAfterSave`)
**Ce que c'est :** Un flow qui se déclenche **automatiquement** après qu'un enregistrement est sauvegardé en base. L'utilisateur ne le voit pas, il s'exécute en arrière-plan.

**Analogie :** Un "trigger after insert/update" en Apex, mais configuré visuellement.

**Quand s'utiliser :** Quand tu dois créer ou modifier d'**autres enregistrements** en réaction à un changement (ex : créer une tâche quand un Case change de statut).

**Dans ce projet :**
- `Flow_Task_Workflow_FirstTask_Creation` → déclenché sur le **Case** (création/modification) → crée les tâches opérationnelles initiales
- `Flow_Task_Creation_on_New_Email_received` → déclenché sur **EmailMessage** (création) → crée une tâche "Lire email"

---

### 🔹 Record-Triggered Flow — Before Save (`triggerType: RecordBeforeSave`)
**Ce que c'est :** Un flow déclenché **avant** la sauvegarde. Il peut modifier l'enregistrement en cours de sauvegarde directement, sans DML supplémentaire (plus performant).

**Analogie :** Un "trigger before insert/update" en Apex.

**Quand s'utiliser :** Pour modifier des champs **du même enregistrement** qui déclenche le flow.

**Dans ce projet :**
- `Contact_Task_assignment` → déclenché sur **Task** → synchronise le champ `Contact__c` ⚠️ statut : **Draft (inactif)**

---

### 🔹 Autolaunched Flow (`processType: AutoLaunchedFlow`)
**Ce que c'est :** Un flow sans écran, lancé par un autre flow, un Process Builder, du code Apex, ou une API. Il s'exécute en silence.

**Dans ce projet :**
- `Flow_Task_Management_Verify_if_user_is_allowed_to_modify_Op_Task` → lancé par `Display_Progress` comme **Screen Action** pour vérifier les droits en temps réel

---

### 🔹 Process Builder migré (`processType: Workflow`)
**Ce que c'est :** Un ancien Process Builder converti en Flow par Salesforce lors de la migration automatique. Le type `Workflow` indique que c'est une automatisation héritée.

**⚠️ À savoir :** Salesforce a déprécié Process Builder. Ces flows doivent être migrés vers des **Record-Triggered Flows** modernes.

**Dans ce projet :**
- `Task_AutomationProcess` → déclenché sur **Task** → met à jour Opportunity et Account

---

### Tableau récapitulatif des types

| Type | Déclenché par | Écran utilisateur | Peut modifier d'autres objets |
|---|---|---|---|
| Screen Flow | Bouton / composant | ✅ Oui | ✅ Oui |
| After Save | Sauvegarde d'enregistrement | ❌ Non | ✅ Oui |
| Before Save | Sauvegarde d'enregistrement | ❌ Non | ⚠️ Seulement l'objet déclencheur |
| Autolaunched | Autre flow / Apex / API | ❌ Non | ✅ Oui |
| Process Builder (legacy) | Sauvegarde d'enregistrement | ❌ Non | ✅ Oui |

---

## 2. Les objets clés du système de tâches

### Objets Salesforce standard utilisés
| Objet | Description |
|---|---|
| `Case` | Le dossier client — objet central autour duquel tout s'organise |
| `Task` | Tâche Salesforce standard (activité) |
| `EmailMessage` | Email lié à un Case (Email-to-Case) |
| `User` | Utilisateur Salesforce |
| `Group` | Groupe / Queue Salesforce |
| `GroupMember` | Appartenance d'un utilisateur à une Queue |
| `UserRecordAccess` | Table système qui indique si un utilisateur a accès en édition à un enregistrement |

### Objets custom du système de tâches
| Objet | Description |
|---|---|
| `Operational_Task__c` | La tâche opérationnelle custom — c'est l'objet central du système. Différent de la Task standard. |
| `Workflow__c` | Modèle de workflow = ensemble ordonné de tâches types à accomplir pour un type de Case |
| `Workflow_Task__c` | Une étape du workflow (tâche type) avec SLA, assignataire par défaut, ordre, etc. |
| `Workflow_Task_Assignee__c` | Liste restreinte d'utilisateurs autorisés à prendre une Workflow_Task spécifique |
| `Task_Outcome__c` | Résultat possible lors de la fermeture d'une tâche (ex : "Résolu", "Escaladé", "Annulé") |
| `Outcome_to_WF_Tasks__c` | Lien entre un outcome et les tâches suivantes à créer automatiquement |
| `SubsidiarySettings__mdt` | Custom Metadata Type — configuration par filiale (code ISO, paramètres pays) |

### Custom Labels clés
| Label | Rôle |
|---|---|
| `Task_Management_Enabled_Countries_RecordTypes` | Liste des RecordTypes de Case éligibles au système de tâches |
| `Task_Management_Enabled_Countries_RecordTypes_For_Closed_Case` | RecordTypes éligibles pour le workflow "email sur case rouvert" |

---

## 3. Documentation : Système Flow_Task_Management

### Vue d'ensemble
Le système Flow_Task_Management est un **moteur de tâches opérationnelles** construit sur Salesforce pour gérer le traitement des Cases. Il crée, suit, assigne et ferme des tâches structurées (`Operational_Task__c`) liées à des Cases, selon des workflows configurés par pays/filiale.

Il se compose de **11 flows** répartis en 3 couches :

```
┌──────────────────────────────────────────┐
│  COUCHE 1 — Déclenchement automatique    │
│  (Record-Triggered Flows)                │
│  → Crée les tâches en arrière-plan       │
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
│  COUCHE 2 — Affichage & orchestration    │
│  (Display_Progress — Screen Flow)        │
│  → Tableau de bord sur la page Case      │
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
│  COUCHE 3 — Actions utilisateur          │
│  (Screen Flows lancés depuis le tableau) │
│  → Créer, assigner, fermer une tâche     │
└──────────────────────────────────────────┘
```

---

### COUCHE 1 — Flows automatisés

#### `Flow_Task_Workflow_FirstTask_Creation`
**Type :** Record-Triggered (After Save) sur `Case`
**Rôle :** Chef d'orchestre des tâches — réagit à tous les événements clés sur un Case.

**Quand se déclenche-t-il ?**
Le Case doit avoir un `RecordType.Name` dans `Task_Management_Enabled_Countries_RecordTypes`, ET au moins une de ces conditions est vraie :
- Nouveau Case créé
- Changement de `Type`, `External_Case_Type__c`, `External_Case_Category__c`, `External_Case_Detail__c`
- Changement de propriétaire (`OwnerId`)
- Statut = "Closed"

**Ce qu'il fait selon le scénario :**

| Scénario | Action |
|---|---|
| **Case créé ou requalifié** | Cherche le Workflow correspondant → crée les premières tâches (`Is_First_Task__c = true`) avec SLA calculé en heures ouvrées |
| **Propriétaire du Case changé** | Réassigne les tâches automatiques ouvertes ayant `Reassign_Task_when_Case_owner_Change__c = true` |
| **Requalification du Case** | Annule toutes les tâches automatiques ouvertes (outcome = "Canceled due to case re-qualification") |
| **Case fermé** | Complète toutes les tâches opérationnelles ouvertes |

**Logique de recherche du Workflow (cascade 3 niveaux) :**
```
Niveau 1 (le plus précis) : Type + Category + Details → si trouvé, utiliser
Niveau 2 (intermédiaire)  : Type + Category           → si trouvé, utiliser
Niveau 3 (le plus large)  : Type uniquement           → si trouvé, utiliser
                            Si aucun → ne rien créer
```

---

#### `Flow_Task_Creation_on_New_Email_received`
**Type :** Record-Triggered (After Save) sur `EmailMessage`
**Rôle :** Crée automatiquement une tâche "Lire email" à chaque réception d'un email entrant sur un Case.

**Condition d'éligibilité :** Le `RecordType` du Case parent doit être dans `Task_Management_Enabled_Countries_RecordTypes`.

**Deux chemins selon l'état du Case :**

| Chemin | Condition | Action |
|---|---|---|
| **Case ouvert** | Statut ≠ "Reopened" | Crée une tâche "Read Email" avec le workflow "Read Email" de la filiale. Si c'est le 1er email → crée la tâche. Si email suivant et tâche déjà ouverte → ne rien créer (idempotence). |
| **Case rouvert** | Statut = "Reopened" | Utilise un workflow spécifique "Read Email - Closed Case". Réouvre le Case si nécessaire. |

**Protection anti-doublon :** Si une tâche "New Email" non complétée existe déjà sur le Case → le flow ne crée pas de doublon.

---

#### `Contact_Task_assignment` ⚠️ DRAFT — Inactif
**Type :** Record-Triggered (Before Save) sur `Task`
**Rôle :** Synchroniser le champ `Contact__c` (custom) sur la Task standard Salesforce quand `WhoId` pointe vers un Contact (préfixe "003").
**Statut :** Non déployé en production. À investiguer avant activation.

---

#### `Task_AutomationProcess` — Legacy Process Builder
**Type :** Process Builder migré (`processType: Workflow`) sur `Task`
**Rôle :** Deux automatisations héritées sur les Tasks Salesforce standard :

| Règle | Condition | Action |
|---|---|---|
| **IsTaskCompletedAndRelatedToOpportunity** | Task complétée + liée à une Opportunity de renouvellement | Met `Contacted__c = true` sur l'Opportunity |
| **AccountSubStatusUpdate** | Task liée à un Account avec `SUB_Status__c = 'Former customer'` et filiale `62001` | Passe `SUB_Status__c = 'To Reconquer'` |

**Bypass :** Le champ `Bypass_Workflow__c` sur l'utilisateur permet de désactiver ces règles (utile pour les admins et intégrations).

> ⚠️ **À moderniser** : Ce flow de type Process Builder doit être migré vers un Record-Triggered Flow moderne.

---

### COUCHE 2 — Tableau de bord

#### `Flow_Task_Management_Display_Progress`
**Type :** Screen Flow embarqué comme composant sur la page **Case**
**Rôle :** Tableau de bord central de gestion des tâches sur un Case.

**Ce qu'il affiche :**
- La liste de toutes les `Operational_Task__c` liées au Case (triées par date de début décroissante)
- Pour chaque tâche : Nom, Statut, Dates (début / échéance / completion), Propriétaire, Outcome

**Boutons disponibles (conditionnels) :**

| Bouton | Flow lancé | Condition d'activation |
|---|---|---|
| **+ Create Task** | `Create_Manual_Task` | Toujours disponible |
| **Assign to me** | `Assign_Task_to_running_User` | Tâche sélectionnée + non complétée + utilisateur autorisé + pas déjà propriétaire |
| **Assign to...** | `Assign_Task_to_another_User` | Tâche sélectionnée + non complétée + utilisateur autorisé |
| **Close Task** | `Close_Operational_Task` | Tâche sélectionnée + non complétée + utilisateur autorisé |

**Vérification des droits en temps réel :**
À chaque sélection de tâche, le flow appelle `Verify_if_user_is_allowed_to_modify_Op_Task` comme **Screen Action** (sans quitter la page) pour déterminer si les boutons doivent être actifs ou grisés.

**Composant tiers utilisé :** `joshdaymentlabs:flowLauncher` — lance les flows enfants en fenêtre modale sans naviguer hors de la page.

---

### COUCHE 3 — Actions utilisateur

#### `Flow_Task_Management_Create_Manual_Task`
**Type :** Screen Flow lancé depuis le bouton "+ Create Task" sur `Display_Progress`
**Rôle :** Créer une tâche opérationnelle ad hoc sur un Case (hors workflow automatique).

**Étapes du formulaire :**
1. Récupération du Case et des queues/utilisateurs filtrés par pays (code ISO de la filiale)
2. Écran de saisie : Sujet, Date début, Date échéance, Assigné à (Queue ou User)
3. Création de l'`Operational_Task__c` avec :
   - `Automatic_Task__c = false` (tâche manuelle)
   - `Only_Available_For_Task_Owners__c = true` (réservée aux propriétaires)
   - `Reassign_Task_when_Case_owner_Change__c = false` (ne suit pas les changements de propriétaire)

---

#### `Flow_Task_Management_Assign_Task_to_running_User`
**Type :** Screen Flow lancé depuis le bouton "Assign to me"
**Rôle :** Permettre à l'utilisateur courant de s'auto-assigner une tâche en un clic.

**Étapes :**
1. Affiche un écran de confirmation : _"Vous êtes sur le point d'assigner la tâche [Nom] à [Votre nom]"_
2. Sur confirmation → met à jour `OwnerId = $User.Id`
3. En cas d'erreur → affiche un écran d'erreur

---

#### `Flow_Task_Management_Assign_Task_to_another_User`
**Type :** Screen Flow lancé depuis le bouton "Assign to..."
**Rôle :** Réassigner une tâche à un autre utilisateur ou une queue, filtrés par pays/filiale.

**Logique de filtrage :**
- Récupère le code ISO de la filiale du Case via `SubsidiarySettings__mdt`
- Filtre les queues dont le nom commence par ce code ISO
- Filtre les utilisateurs actifs de la même filiale (`Subsidiary_Indicator__c`)

**Deux chemins selon la restriction d'assignataires :**

| `Don_t_Restrict_Assignment__c` | Comportement |
|---|---|
| `false` (restriction active) | Affiche uniquement les assignataires listés dans `Workflow_Task_Assignee__c` |
| `true` (pas de restriction) | Affiche tous les utilisateurs/queues de la filiale |

---

#### `Flow_Task_Management_Close_Operational_Task`
**Type :** Screen Flow lancé depuis le bouton "Close Task"
**Rôle :** Fermeture guidée d'une tâche avec gestion des outcomes et création des tâches suivantes.

**Étapes (flux le plus complexe du système) :**

```
1. Récupère la tâche et le Case
       ↓
2. La tâche a-t-elle un Workflow_Task__c associé ?
   → Non : fermer directement
   → Oui : récupérer les outcomes possibles
       ↓
3. Des outcomes existent-ils ?
   → Non : fermer directement
   → Oui : afficher la liste des outcomes à sélectionner
       ↓
4. L'outcome sélectionné ferme-t-il le Case ?
   → Non : aller à l'étape 7
   → Oui : vérifier les tâches obligatoires encore ouvertes
       ↓
5. Des tâches bloquantes (Must_be_closed_before_case_can_be_closed__c) sont-elles ouvertes ?
   → Oui : bloquer la fermeture et afficher un message
   → Non : continuer
       ↓
6. L'outcome crée-t-il de nouvelles tâches ? (Outcome_to_WF_Tasks__c)
   → Oui : calculer SLA + créer les nouvelles Operational_Task__c
       ↓
7. Faut-il mettre à jour le Case ? (statut, step workflow, raison de réouverture)
   → Oui : mettre à jour le Case
       ↓
8. Fermer la tâche courante : Closed_by__c, Completion_Date__c, Task_Outcome__c
```

---

#### `Flow_Task_Management_Mass_Assign_tasks_to_me_from_list_view`
**Type :** Screen Flow — Action de liste sur `Operational_Task__c`
**Rôle :** Auto-assignation en masse depuis une List View (sélection multiple).

**Logique de vérification d'éligibilité :**
Le flow vérifie que l'utilisateur est membre (direct **ou indirect** via groupe public) des queues propriétaires des tâches sélectionnées. Seules les tâches éligibles sont mises à jour.

**Protection :** Un compteur compare le nombre de tâches sélectionnées vs mises à jour. Si différent → affiche un écran d'erreur explicatif.

---

#### `Flow_Task_Management_Verify_if_user_is_allowed_to_modify_Op_Task`
**Type :** Autolaunched Flow — appelé comme Screen Action par `Display_Progress`
**Rôle :** Renvoyer un booléen `Allowed_To_Modify` pour activer/désactiver les boutons.

**Logique :**
```
La tâche est-elle Only_Available_For_Task_Owners__c = true ?
   → Non : Allowed_To_Modify = true (tout le monde peut modifier)
   → Oui : vérifier UserRecordAccess
             ↓
             L'utilisateur a-t-il HasEditAccess sur cet enregistrement ?
             → Oui : Allowed_To_Modify = true
             → Non : Allowed_To_Modify = false
```

---

## 4. Carte des dépendances entre flows

```
DÉCLENCHEURS AUTOMATIQUES
═══════════════════════════════════════════════════════════════

  [Case créé/modifié]
        │
        ▼
  Flow_Task_Workflow_FirstTask_Creation
        │
        ├──→ Crée Operational_Task__c (premières tâches)
        ├──→ Annule Operational_Task__c (requalification)
        ├──→ Réassigne Operational_Task__c (changement owner)
        └──→ Ferme Operational_Task__c (Case fermé)
        │
        └── [Apex] profFlow_bhAdd__addBusinessHours (calcul SLA)

  [EmailMessage entrant créé]
        │
        ▼
  Flow_Task_Creation_on_New_Email_received
        │
        └──→ Crée Operational_Task__c "Lire email"
        │
        └── [Apex] profFlow_bhAdd__addBusinessHours (calcul SLA)

  [Task créée/modifiée]
        │
        ├──▼ Contact_Task_assignment ⚠️ DRAFT
        │      └──→ Synchronise Contact__c sur Task
        │
        └──▼ Task_AutomationProcess (legacy)
               ├──→ Met à jour Opportunity (Contacted__c)
               └──→ Met à jour Account (SUB_Status__c)


TABLEAU DE BORD (page Case)
═══════════════════════════════════════════════════════════════

  Flow_Task_Management_Display_Progress
        │
        ├── [Screen Action temps réel]
        │       └──▶ Verify_if_user_is_allowed_to_modify_Op_Task
        │                  └── retourne Allowed_To_Modify (bool)
        │
        ├── [Bouton modal] ──▶ Create_Manual_Task
        ├── [Bouton modal] ──▶ Assign_Task_to_running_User
        ├── [Bouton modal] ──▶ Assign_Task_to_another_User
        └── [Bouton modal] ──▶ Close_Operational_Task
                                    │
                                    ├──→ Crée nouvelles Operational_Task__c
                                    ├──→ Met à jour Case
                                    └── [Apex] profFlow_bhAdd__addBusinessHours
```

---

## 5. Concepts avancés rencontrés

### 📘 Concept : Screen Action (Flow dans un Flow en temps réel)
Une **Screen Action** est un Autolaunched Flow appelé **depuis l'intérieur d'un écran**, sans quitter la page. Il s'exécute à chaque interaction utilisateur (ex : sélection d'une ligne dans un tableau) et peut retourner des valeurs utilisées pour conditionner l'affichage.

**Dans ce projet :** `Display_Progress` appelle `Verify_if_user_is_allowed` à chaque sélection de tâche pour savoir si les boutons doivent être actifs.

---

### 📘 Concept : Transform (élément Flow)
L'élément **Transform** permet de convertir une collection d'un type d'objet en une collection d'un autre type, avec un mapping de champs. C'est l'équivalent d'un `.map()` en JavaScript.

**Dans ce projet :** `Transform_WF_Task_to_Operational_Tasks` convertit une liste de `Workflow_Task__c` (modèles) en liste d'`Operational_Task__c` (instances réelles à créer).

---

### 📘 Concept : Apex Invocable Action
Une **Apex Action** dans un Flow est une méthode Apex annotée `@InvocableMethod`, appelable depuis un flow comme n'importe quel autre élément. Elle permet d'exécuter de la logique complexe impossible à faire nativement dans un Flow.

**Dans ce projet :** `profFlow_bhAdd__addBusinessHours` (package externe `profFlow_bhAdd`) calcule une date/heure d'échéance en ajoutant un nombre d'heures **ouvrées** à partir d'une date de départ, en tenant compte des Business Hours Salesforce.

**Paramètres :**
- `businessHoursId` : ID des Business Hours Salesforce configurées
- `intervalMilliseconds` : durée du SLA en millisecondes (ex : SLA en heures × 3 600 000)
- `startDateTime` : date de départ (généralement la date de création de la tâche)

---

### 📘 Concept : Custom Metadata Type (CMDT)
Les **Custom Metadata Types** (`__mdt`) sont des tables de configuration déployables avec du code. Contrairement aux Custom Settings, elles sont visibles dans les packages et peuvent être utilisées dans les formules et les flows.

**Dans ce projet :** `SubsidiarySettings__mdt` stocke la configuration par filiale (code ISO, paramètres pays) utilisée pour filtrer les queues et utilisateurs dans les flows d'assignation.

---

### 📘 Concept : UserRecordAccess
`UserRecordAccess` est un **objet système Salesforce** (non modifiable) qui indique si un utilisateur spécifique a accès en lecture, édition ou suppression sur un enregistrement donné. On peut l'interroger dans un SOQL comme une table normale.

**Dans ce projet :** `Verify_if_user_is_allowed` interroge `UserRecordAccess` pour savoir si l'utilisateur courant a `HasEditAccess = true` sur la tâche sélectionnée.

---

### 📘 Concept : Idempotence dans les flows automatisés
L'**idempotence** signifie qu'exécuter la même action plusieurs fois doit produire le même résultat qu'une seule exécution (pas de doublons, pas d'effets de bord).

**Dans ce projet :** `Flow_Task_Creation_on_New_Email_received` vérifie toujours si une tâche "New Email" ouverte existe déjà avant d'en créer une nouvelle. Cela évite de créer plusieurs tâches si plusieurs emails arrivent rapidement.

---

### 📘 Concept : Appartenance directe vs indirecte à une Queue
Dans Salesforce, un utilisateur peut appartenir à une Queue :
- **Directement** : il est membre explicite de la Queue (`GroupMember` avec `GroupId = queueId`)
- **Indirectement** : il est membre d'un Groupe Public, lui-même ajouté à la Queue

`Flow_Task_Management_Mass_Assign_tasks_to_me_from_list_view` gère les deux niveaux d'appartenance pour correctement valider qu'un utilisateur peut prendre en charge une tâche appartenant à une queue.

---

*Ce fichier est destiné à évoluer. Ajoute un nouveau chapitre à chaque concept Salesforce rencontré dans le projet.*
