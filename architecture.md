# Architecture — Système Flow_Task_Management
> Documentation technique et métier du système de gestion des tâches opérationnelles sur les Cases Salesforce.

---

## Table des matières
1. [Vue métier — Pourquoi ce système existe](#1-vue-métier--pourquoi-ce-système-existe)
2. [Vue d'ensemble de l'architecture](#2-vue-densemble-de-larchitecture)
3. [Les objets et leurs relations](#3-les-objets-et-leurs-relations)
4. [Les flows et leurs relations](#4-les-flows-et-leurs-relations)
5. [Relation entre les Flows et les Workflows](#5-relation-entre-les-flows-et-les-workflows)
6. [Cycles de vie](#6-cycles-de-vie)
7. [Commandes SOQL — exploration de l'architecture](#7-commandes-soql--exploration-de-larchitecture)

---

## 1. Vue métier — Pourquoi ce système existe

### Le problème métier
Quand un client ouvre un dossier (Case), plusieurs agents de différentes équipes doivent intervenir dans un ordre précis : lire l'email, appeler le client, vérifier les documents, escalader si nécessaire... Sans système, chaque équipe gérait ses propres listes de tâches en dehors de Salesforce, ce qui créait des oublis et un manque de visibilité.

### La solution
Le système **Flow_Task_Management** automatise la création et le suivi de tâches opérationnelles directement dans Salesforce, attachées aux Cases. Il garantit que :
- Les bonnes tâches sont créées automatiquement selon le type de dossier et le pays
- Chaque tâche a un délai SLA calculé en heures ouvrées
- Un agent ne peut pas fermer un dossier tant que les tâches bloquantes sont ouvertes
- Quand une tâche est fermée, les tâches suivantes sont créées automatiquement selon le résultat

### Les acteurs
| Acteur | Rôle dans le système |
|---|---|
| **Agent / Chargé de clientèle** | Voit et traite les tâches sur la page Case, s'assigne des tâches, les ferme avec un outcome |
| **Superviseur / Team Lead** | Peut réassigner les tâches entre agents ou queues |
| **Administrateur Salesforce** | Configure les workflows, les tâches modèles, les SLAs et les outcomes |
| **Le système (flows automatiques)** | Crée les tâches à l'ouverture d'un Case ou en réponse à des événements |

---

## 2. Vue d'ensemble de l'architecture

Le système est organisé en **3 couches** qui interagissent entre elles :

```
╔══════════════════════════════════════════════════════════════════════╗
║  COUCHE 1 — CONFIGURATION (données statiques, gérées par les admins) ║
║                                                                      ║
║   Workflow__c ─────────────── Workflow_Task__c                       ║
║   (scénario par pays/type)    (étapes modèles avec SLA)              ║
║          │                            │                              ║
║          └────────────────────────────┤                              ║
║                                       │                              ║
║                              Task_Outcome__c                         ║
║                              (résultats possibles)                   ║
║                                       │                              ║
║                              Outcome_to_WF_Tasks__c                  ║
║                              (lien outcome → tâche suivante)         ║
╚══════════════════════════════════════════════════════════════════════╝
                          ↓ les flows lisent cette config ↓
╔══════════════════════════════════════════════════════════════════════╗
║  COUCHE 2 — AUTOMATISATION (flows déclenchés par des événements)     ║
║                                                                      ║
║   [Case créé/modifié]                                                ║
║         └──→ Flow_Task_Workflow_FirstTask_Creation                   ║
║                   └──→ crée les Operational_Task__c initiales        ║
║                                                                      ║
║   [Email entrant reçu]                                               ║
║         └──→ Flow_Task_Creation_on_New_Email_received                ║
║                   └──→ crée une tâche "Lire email"                   ║
╚══════════════════════════════════════════════════════════════════════╝
                          ↓ crée et met à jour ↓
╔══════════════════════════════════════════════════════════════════════╗
║  COUCHE 3 — INTERACTION UTILISATEUR (flows lancés par les agents)    ║
║                                                                      ║
║   Page Case → Display_Progress (tableau de bord)                     ║
║         ├──→ Create_Manual_Task       (créer une tâche ad hoc)       ║
║         ├──→ Assign_Task_to_me        (s'auto-assigner)              ║
║         ├──→ Assign_Task_to_another   (réassigner)                   ║
║         └──→ Close_Operational_Task   (fermer + créer la suivante)   ║
║                                                                      ║
║   List View → Mass_Assign_to_me       (prise en charge en masse)     ║
╚══════════════════════════════════════════════════════════════════════╝
                          ↓ lit et modifie ↓
╔══════════════════════════════════════════════════════════════════════╗
║  DONNÉES VIVANTES                                                    ║
║                                                                      ║
║   Case ──────────────────── Operational_Task__c                      ║
║   (dossier client)           (tâche réelle sur le dossier)           ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## 3. Les objets et leurs relations

### Schéma des relations

```
BusinessHours
    │ (lookup)
    │
Workflow__c ──────────────────────────────────────────────┐
    │  Subsidiary_Indicator__c                             │
    │  Type__c                                             │
    │  Category__c                                         │
    │  Details__c                                          │
    │                                                      │
    │ (1 workflow)                                         │
    │                                                      │
    ├──── Workflow_Task__c (N tâches modèles) ─────────────┤
    │         │  Task_Subject__c                           │
    │         │  Task_SLA__c                               │
    │         │  Is_First_Task__c                          │
    │         │  Default_queue_ID__c                       │
    │         │  Must_be_closed_before_case_can_be_closed  │
    │         │                                            │
    │         │ (1 tâche modèle)                           │
    │         │                                            │
    │         ├──── Task_Outcome__c (N outcomes)           │
    │         │         │  Name                            │
    │         │         │  Outcome_will_close_Case__c      │
    │         │         │  Case_Status__c                  │
    │         │         │                                  │
    │         │         └──── Outcome_to_WF_Tasks__c ──────┘
    │         │                   (lien many-to-many)
    │         │                   outcome → Workflow_Task à créer
    │         │
    │         └──── Workflow_Task_Assignee__c
    │                   (liste restreinte d'assignataires autorisés)
    │
Case ──────────────────────────────────────────────────────
    │  Type
    │  External_Case_Category__c
    │  External_Case_Detail__c
    │  Subsidiary_Indicator__c
    │  Status
    │
    └──── Operational_Task__c (N tâches réelles par Case)
              │  Name
              │  Status__c (formule)
              │  Start_Date__c
              │  Due_Date__c
              │  Completion_Date__c
              │  Task_SLA__c
              │  Automatic_Task__c
              │  Task_Outcome__c
              │
              ├── (lookup) → Workflow_Task__c  [modèle source]
              ├── (lookup) → User              [assignataire individuel]
              ├── (lookup) → Queue             [assignataire queue]
              └── (owned by) → User ou Queue  [OwnerId]
```

### Description détaillée des objets

#### `Workflow__c` — Scénario de traitement
**Rôle métier :** Définit la "recette" de traitement pour un type de dossier dans un pays donné.
**Rôle technique :** Table de routing — le flow l'interroge pour savoir quelles tâches créer.

| Champ | Technique | Métier |
|---|---|---|
| `Name` | Text | Nom du scénario (ex: "Réclamation Véhicule FRA") |
| `Type__c` | Text — matche `Case.Type` | Type de dossier concerné |
| `Category__c` | Text — matche `Case.External_Case_Category__c` | Catégorie du dossier (optionnel) |
| `Details__c` | Text — matche `Case.External_Case_Detail__c` | Détail du dossier (optionnel) |
| `Subsidiary_Indicator__c` | Text — code filiale | Pays/filiale concerné |
| `Business_Hours__c` | Lookup → BusinessHours | Heures ouvrées pour le calcul des SLAs |

---

#### `Workflow_Task__c` — Étape modèle
**Rôle métier :** Décrit une tâche type que les agents doivent accomplir dans le cadre d'un scénario.
**Rôle technique :** Modèle utilisé pour instancier les `Operational_Task__c`.

| Champ | Technique | Métier |
|---|---|---|
| `Task_Subject__c` | Text | Intitulé de la tâche affiché à l'agent |
| `Task_Description__c` | Text | Instructions détaillées pour l'agent |
| `Task_SLA__c` | Number (heures) | Délai maximum pour accomplir la tâche |
| `Default_queue_ID__c` | Text (ID Queue) | Équipe par défaut assignée à cette tâche |
| `Is_First_Task__c` | Checkbox | Cette tâche démarre dès l'ouverture du dossier |
| `Must_be_closed_before_case_can_be_closed__c` | Checkbox | Le dossier ne peut pas être fermé tant que cette tâche est ouverte |
| `Only_Available_For_Task_Owners__c` | Checkbox | Seul le propriétaire actuel peut modifier cette tâche |
| `Don_t_Restrict_Assignment__c` | Checkbox (défaut: true) | Si décoché, seuls les agents listés dans `Workflow_Task_Assignee__c` peuvent prendre la tâche |
| `Reassign_Task_when_Case_owner_Change__c` | Checkbox (défaut: true) | La tâche suit automatiquement le propriétaire du Case |

---

#### `Task_Outcome__c` — Résultat de fermeture
**Rôle métier :** Les choix disponibles quand un agent ferme une tâche (ex: "Résolu", "Escaladé", "Client non joignable").
**Rôle technique :** Détermine quelle(s) tâche(s) créer ensuite et si le Case doit être mis à jour.

---

#### `Outcome_to_WF_Tasks__c` — Chaînage outcome → tâche
**Rôle métier :** Définit les étapes suivantes après un résultat. Un même outcome peut déclencher plusieurs tâches en parallèle.
**Rôle technique :** Table de jointure many-to-many entre `Task_Outcome__c` et `Workflow_Task__c`.

---

#### `Operational_Task__c` — La tâche réelle
**Rôle métier :** La tâche concrète qu'un agent voit et traite sur la page d'un Case.
**Rôle technique :** Instance créée à partir d'un modèle `Workflow_Task__c`, liée à un Case précis.

| Champ | Technique | Métier |
|---|---|---|
| `Status__c` | Formule calculée | État actuel : To do 🟨 / Overdue 🟥 / Completed ✅ |
| `Start_Date__c` | DateTime | Date/heure de création de la tâche |
| `Due_Date__c` | DateTime (calculé via Apex) | Date/heure limite (Start + SLA en heures ouvrées) |
| `Completion_Date__c` | DateTime | Date/heure de fermeture (renseignée par le flow Close) |
| `Age_in_Hours__c` | Formule | Durée réelle de traitement en heures |
| `Task_SLA__c` | Number | SLA en heures (copié depuis le modèle) |
| `Automatic_Task__c` | Checkbox | true = créée par automatisme, false = créée manuellement |
| `Task_Outcome__c` | Text | Résultat choisi à la fermeture |
| `Closed_by__c` | Text | Nom de l'agent qui a fermé la tâche |
| `Workflow_Task__c` | Lookup | Modèle source (null si tâche manuelle) |

---

### Matrice des relations entre objets

| Objet A | Relation | Objet B | Cardinalité | Sens |
|---|---|---|---|---|
| `Workflow__c` | Parent de | `Workflow_Task__c` | 1 → N | Un workflow contient plusieurs étapes |
| `Workflow_Task__c` | Parent de | `Task_Outcome__c` | 1 → N | Une étape a plusieurs outcomes possibles |
| `Task_Outcome__c` | Lié à | `Workflow_Task__c` (via `Outcome_to_WF_Tasks__c`) | N → N | Un outcome déclenche N tâches suivantes |
| `Workflow_Task__c` | Modèle de | `Operational_Task__c` | 1 → N | Un modèle peut être instancié sur plusieurs Cases |
| `Case` | Parent de | `Operational_Task__c` | 1 → N | Un Case a plusieurs tâches opérationnelles |
| `User/Queue` | Propriétaire de | `Operational_Task__c` | 1 → N | Un utilisateur ou une queue gère plusieurs tâches |

---

## 4. Les flows et leurs relations

### Carte complète des flows

```
╔══════════════════════════════════════════════════════════════════════╗
║  FLOWS AUTOMATIQUES — déclenchés par des événements Salesforce       ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Flow_Task_Workflow_FirstTask_Creation                               ║
║  ├── Déclenché sur : Case (After Save — création + modification)     ║
║  ├── Lit    : Workflow__c, Workflow_Task__c                          ║
║  ├── Crée   : Operational_Task__c                                    ║
║  ├── Modifie: Operational_Task__c (annulation, réassignation)        ║
║  └── Appelle: [Apex] profFlow_bhAdd__addBusinessHours                ║
║                                                                      ║
║  Flow_Task_Creation_on_New_Email_received                            ║
║  ├── Déclenché sur : EmailMessage (After Save — création)            ║
║  ├── Lit    : Workflow__c, Workflow_Task__c, Operational_Task__c     ║
║  ├── Crée   : Operational_Task__c                                    ║
║  ├── Modifie: Case (statut → Reopened si besoin)                     ║
║  └── Appelle: [Apex] profFlow_bhAdd__addBusinessHours                ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  FLOW DE TABLEAU DE BORD — affiché sur la page Case                  ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Flow_Task_Management_Display_Progress                               ║
║  ├── Type : Screen Flow embarqué sur la page Case                    ║
║  ├── Lit   : Case, Operational_Task__c                               ║
║  ├── Appelle (Screen Action) :                                       ║
║  │       └── Verify_if_user_is_allowed_to_modify_Op_Task             ║
║  └── Lance (boutons modaux) :                                        ║
║           ├── Flow_Task_Management_Create_Manual_Task                ║
║           ├── Flow_Task_Management_Assign_Task_to_running_User       ║
║           ├── Flow_Task_Management_Assign_Task_to_another_User       ║
║           └── Flow_Task_Management_Close_Operational_Task            ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  FLOWS D'ACTION — lancés depuis Display_Progress                     ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Flow_Task_Management_Create_Manual_Task                             ║
║  ├── Lancé depuis : bouton sur Display_Progress (contexte : Case)    ║
║  ├── Lit    : Case, SubsidiarySettings__mdt, QueueSobject, User      ║
║  └── Crée   : Operational_Task__c (Automatic_Task__c = false)        ║
║                                                                      ║
║  Flow_Task_Management_Assign_Task_to_running_User                    ║
║  ├── Lancé depuis : bouton "Assign to me" sur Display_Progress       ║
║  └── Modifie: Operational_Task__c.OwnerId ← $User.Id                ║
║                                                                      ║
║  Flow_Task_Management_Assign_Task_to_another_User                    ║
║  ├── Lancé depuis : bouton "Assign to..." sur Display_Progress       ║
║  ├── Lit    : SubsidiarySettings__mdt, QueueSobject, User,           ║
║  │            Workflow_Task_Assignee__c                              ║
║  └── Modifie: Operational_Task__c.OwnerId                            ║
║                                                                      ║
║  Flow_Task_Management_Close_Operational_Task                         ║
║  ├── Lancé depuis : bouton "Close Task" sur Display_Progress         ║
║  ├── Lit    : Operational_Task__c, Case, Task_Outcome__c,            ║
║  │            Outcome_to_WF_Tasks__c, Workflow_Task__c               ║
║  ├── Crée   : Operational_Task__c (tâches suivantes)                 ║
║  ├── Modifie: Operational_Task__c (ferme la tâche courante)          ║
║  ├── Modifie: Case (statut, step, raison si l'outcome le demande)    ║
║  └── Appelle: [Apex] profFlow_bhAdd__addBusinessHours                ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  FLOWS UTILITAIRES                                                   ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Flow_Task_Management_Verify_if_user_is_allowed_to_modify_Op_Task    ║
║  ├── Type : Autolaunched — appelé comme Screen Action                ║
║  ├── Appelé par : Display_Progress (à chaque sélection de tâche)     ║
║  ├── Lit    : Operational_Task__c, UserRecordAccess                  ║
║  └── Retourne: Allowed_To_Modify (Boolean)                           ║
║                                                                      ║
║  Flow_Task_Management_Mass_Assign_tasks_to_me_from_list_view         ║
║  ├── Type : Screen Flow — action de liste sur Operational_Task__c    ║
║  ├── Lit    : GroupMember (appartenance directe et indirecte)        ║
║  └── Modifie: Operational_Task__c.OwnerId ← $User.Id (en masse)     ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Matrice des relations entre flows

| Flow appelant | Flow appelé | Type d'appel | Condition |
|---|---|---|---|
| `Display_Progress` | `Verify_if_user_is_allowed` | Screen Action (temps réel) | À chaque sélection de tâche |
| `Display_Progress` | `Create_Manual_Task` | Bouton modal | Clic sur "+ Create Task" |
| `Display_Progress` | `Assign_Task_to_running_User` | Bouton modal | Clic sur "Assign to me" |
| `Display_Progress` | `Assign_Task_to_another_User` | Bouton modal | Clic sur "Assign to..." |
| `Display_Progress` | `Close_Operational_Task` | Bouton modal | Clic sur "Close Task" |

> Les flows automatiques (`FirstTask_Creation`, `New_Email`) ne sont appelés par aucun autre flow — ils sont déclenchés directement par Salesforce via les triggers Record-Triggered.

---

## 5. Relation entre les Flows et les Workflows

Les **Flows** et les **Workflows** (`Workflow__c`) jouent des rôles complémentaires et distincts :

```
WORKFLOW__C                         FLOWS
(configuration métier)              (moteur d'exécution)
─────────────────────               ─────────────────────
Définit QUOI créer           ──→    Décide QUAND créer
Définit le SLA               ──→    Calcule la Due Date
Définit l'assignataire       ──→    Applique l'assignataire
Définit les outcomes         ──→    Affiche les choix à l'agent
Définit les enchaînements    ──→    Crée les tâches suivantes
```

### Points d'interaction précis

| Flow | Objet Workflow lu | Champ utilisé | Utilisation |
|---|---|---|---|
| `FirstTask_Creation` | `Workflow__c` | `Type__c`, `Category__c`, `Details__c`, `Subsidiary_Indicator__c` | Trouver quel workflow s'applique au Case |
| `FirstTask_Creation` | `Workflow__c` | `Business_Hours__c` | Passer aux Apex pour calculer la Due Date |
| `FirstTask_Creation` | `Workflow_Task__c` | `Is_First_Task__c` | Filtrer les tâches à créer au démarrage |
| `FirstTask_Creation` | `Workflow_Task__c` | `Task_SLA__c`, `Default_queue_ID__c`, tous les flags | Remplir les champs des `Operational_Task__c` créées |
| `New_Email_received` | `Workflow__c` | `Type__c` contient "Read Email" | Trouver le workflow "lecture d'email" |
| `New_Email_received` | `Workflow_Task__c` | `Is_First_Task__c` | Récupérer la première tâche du workflow email |
| `Close_Operational_Task` | `Task_Outcome__c` | `Name`, `Outcome_will_close_Case__c` | Afficher les choix de fermeture |
| `Close_Operational_Task` | `Outcome_to_WF_Tasks__c` | `Workflow_Task__c` | Identifier les tâches à créer après fermeture |
| `Close_Operational_Task` | `Workflow_Task__c` | Tous les champs | Créer les tâches suivantes |
| `Assign_Task_to_another_User` | — | — | Ne lit pas les Workflows |
| `Display_Progress` | — | — | Ne lit pas les Workflows |

### Résumé de la dépendance

```
Sans Workflow__c configuré
       → FirstTask_Creation ne crée aucune tâche
       → Le Case s'ouvre sans tâches automatiques

Sans Workflow_Task__c avec Is_First_Task__c = true
       → Workflow trouvé mais aucune tâche initiale créée

Sans Task_Outcome__c
       → Close_Operational_Task ferme la tâche sans proposer d'outcome
       → Pas de tâches suivantes créées

Sans Outcome_to_WF_Tasks__c
       → L'outcome est enregistré mais aucune tâche suivante n'est créée
```

---

## 6. Cycles de vie

### Cycle de vie d'un Case (du point de vue des tâches)

```
[Case créé]
     │
     ▼
Flow_Task_Workflow_FirstTask_Creation se déclenche
     │
     ├── Workflow trouvé ? ──Non──→ Case sans tâches automatiques
     │
     └── Oui
          │
          ▼
     Tâches initiales créées (Is_First_Task = true)
     Statut : "To do" 🟨
          │
          │  [Agent traite les tâches]
          ▼
     Tâche fermée avec outcome
          │
          ├── Outcome crée des tâches suivantes ?
          │        └── Oui → nouvelles tâches créées → retour à "To do" 🟨
          │
          ├── Outcome met à jour le Case ?
          │        └── Oui → Case.Status / Case.Step mis à jour
          │
          └── Toutes les tâches bloquantes sont-elles fermées ?
                   └── Oui → Case peut être fermé
                              → Flow ferme toutes les tâches ouvertes restantes
```

### Cycle de vie d'une Operational_Task__c

```
CRÉATION
  ├── Automatique : FirstTask_Creation ou New_Email ou Close (tâche suivante)
  │     Automatic_Task__c = true
  │     Workflow_Task__c  = ID du modèle source
  │
  └── Manuelle    : Create_Manual_Task
        Automatic_Task__c = false
        Workflow_Task__c  = null
        Only_Available_For_Task_Owners__c = true
        Reassign_Task_when_Case_owner_Change__c = false

        │
        ▼
STATUT "To do" 🟨
(Start_Date__c renseignée, Completion_Date__c vide, dans les délais)

        │
        ├── Si NOW() > Due_Date__c ──→ STATUT "Overdue" 🟥 (automatique)
        │
        ├── [Agent s'assigne la tâche]
        │     Assign_to_me ou Assign_to_another → OwnerId mis à jour
        │
        └── [Agent ferme la tâche]
              Close_Operational_Task
              → Completion_Date__c renseignée
              → Closed_by__c renseigné
              → Task_Outcome__c renseigné
              ▼
        STATUT "Completed" ✅

ANNULATION (cas spécial)
  Case requalifié → Task_Outcome__c = "Canceled due to case re-qualification"
  + Completion_Date__c renseignée → STATUT "Completed" ✅
```

---

## 7. Commandes SOQL — exploration de l'architecture

### Connexion à l'org

```bash
# Lister les orgs connectées
sf org list

# Se connecter à une org (ouvre un navigateur)
sf org login web --alias <monAlias>
```

---

### Q1 — Quels workflows sont configurés pour mon pays ?

```bash
sf data query \
  --query "SELECT Id, Name, Type__c, Category__c, Details__c,
                  Subsidiary_Indicator__c, Business_Hours__r.Name
           FROM Workflow__c
           WHERE Subsidiary_Indicator__c = 'FRA'
           ORDER BY Type__c, Category__c" \
  --target-org <alias>
```

**Explication :**
- `WHERE Subsidiary_Indicator__c = 'FRA'` → filtre sur le pays (change pour BEL, MEX, etc.)
- `Business_Hours__r.Name` → traverse la relation lookup pour afficher le nom des heures ouvrées
- **Résultat :** liste des scénarios configurés pour la France, regroupés par type de Case

---

### Q2 — Quelles tâches sont créées à l'ouverture d'un Case selon son type ?

```bash
sf data query \
  --query "SELECT Id, Task_Subject__c, Task_SLA__c,
                  Must_be_closed_before_case_can_be_closed__c,
                  Reassign_Task_when_Case_owner_Change__c,
                  Parent_Workflow__r.Name,
                  Parent_Workflow__r.Type__c,
                  Parent_Workflow__r.Subsidiary_Indicator__c
           FROM Workflow_Task__c
           WHERE Is_First_Task__c = true
           ORDER BY Parent_Workflow__r.Subsidiary_Indicator__c,
                    Parent_Workflow__r.Type__c" \
  --target-org <alias>
```

**Explication :**
- `WHERE Is_First_Task__c = true` → uniquement les tâches créées au démarrage
- `Parent_Workflow__r.Type__c` → affiche le type de Case associé sans requête supplémentaire
- **Résultat :** pour chaque pays + type de Case, les tâches qui seront automatiquement créées

---

### Q3 — Quel est l'enchaînement complet d'un workflow ?

```bash
# Étape 1 : récupérer l'ID du workflow
sf data query \
  --query "SELECT Id, Name FROM Workflow__c
           WHERE Type__c = '<TYPE_DU_CASE>'
             AND Subsidiary_Indicator__c = '<CODE_PAYS>'" \
  --target-org <alias>

# Étape 2 : voir toutes les tâches du workflow
sf data query \
  --query "SELECT Id, Name, Task_Subject__c, Task_SLA__c, Is_First_Task__c
           FROM Workflow_Task__c
           WHERE Parent_Workflow__c = '<ID_WORKFLOW>'
           ORDER BY Is_First_Task__c DESC" \
  --target-org <alias>

# Étape 3 : voir les outcomes et leurs enchaînements
sf data query \
  --query "SELECT Outcome__r.Name,
                  Workflow_Task__r.Task_Subject__c,
                  Workflow_Task__r.Task_SLA__c
           FROM Outcome_to_WF_Tasks__c
           WHERE Workflow_Task__r.Parent_Workflow__c = '<ID_WORKFLOW>'
           ORDER BY Outcome__r.Name" \
  --target-org <alias>
```

**Explication :**
- Ces 3 requêtes enchaînées donnent une vue complète du workflow : tâches initiales → outcomes → tâches suivantes
- **Résultat :** le schéma complet d'un scénario de traitement

---

### Q4 — Quelles tâches sont ouvertes et en retard en ce moment ?

```bash
sf data query \
  --query "SELECT Id, Name, Due_Date__c, Age_in_Hours__c,
                  Case__r.CaseNumber, Case__r.Subject,
                  Owner.Name,
                  Subsidiary_Indicator__c
           FROM Operational_Task__c
           WHERE Completion_Date__c = null
             AND Due_Date__c < TODAY
           ORDER BY Due_Date__c ASC
           LIMIT 200" \
  --target-org <alias>
```

**Explication :**
- `Completion_Date__c = null` → tâches non fermées
- `Due_Date__c < TODAY` → dont la date limite est dépassée
- `Case__r.CaseNumber` → numéro du Case sans jointure supplémentaire
- **Résultat :** liste des tâches en retard, triées de la plus ancienne à la plus récente

---

### Q5 — Historique complet des tâches sur un Case précis

```bash
sf data query \
  --query "SELECT Id, Name, Status__c, Start_Date__c, Due_Date__c,
                  Completion_Date__c, Age_in_Hours__c, Task_SLA__c,
                  Task_Outcome__c, Closed_by__c,
                  Automatic_Task__c,
                  Workflow_Task__r.Task_Subject__c,
                  Owner.Name
           FROM Operational_Task__c
           WHERE Case__c = '<ID_DU_CASE>'
           ORDER BY Start_Date__c ASC" \
  --target-org <alias>
```

**Explication :**
- Remplace `<ID_DU_CASE>` par l'ID du Case (commence par `500`)
- `Automatic_Task__c` → distingue les tâches automatiques des manuelles
- `Workflow_Task__r.Task_Subject__c` → null si tâche manuelle
- **Résultat :** l'historique complet du traitement du Case, dans l'ordre chronologique

---

### Q6 — Quels utilisateurs sont autorisés à prendre une tâche restreinte ?

```bash
sf data query \
  --query "SELECT User__r.Name, User__r.Email,
                  Workflow_Task__r.Task_Subject__c,
                  Workflow_Task__r.Parent_Workflow__r.Name
           FROM Workflow_Task_Assignee__c
           WHERE Workflow_Task__c = '<ID_WORKFLOW_TASK>'
           ORDER BY User__r.Name" \
  --target-org <alias>
```

**Explication :**
- Utilisé quand `Workflow_Task__c.Don_t_Restrict_Assignment__c = false`
- **Résultat :** liste des agents autorisés à prendre cette tâche

---

### Récapitulatif — Quelle commande pour quelle question

| Question | Objet à requêter | Filtre principal |
|---|---|---|
| Quels scénarios existent pour ce pays ? | `Workflow__c` | `Subsidiary_Indicator__c` |
| Quelles tâches au démarrage d'un Case ? | `Workflow_Task__c` | `Is_First_Task__c = true` |
| Toutes les étapes d'un workflow | `Workflow_Task__c` | `Parent_Workflow__c` |
| Enchaînements entre tâches | `Outcome_to_WF_Tasks__c` | `Workflow_Task__r.Parent_Workflow__c` |
| Tâches réelles sur un Case | `Operational_Task__c` | `Case__c` |
| Tâches en retard maintenant | `Operational_Task__c` | `Completion_Date__c = null AND Due_Date__c < TODAY` |
| Assignataires autorisés d'une tâche | `Workflow_Task_Assignee__c` | `Workflow_Task__c` |
