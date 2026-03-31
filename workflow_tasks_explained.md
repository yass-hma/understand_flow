# Workflow Tasks Explained
> Comment les tâches par défaut sont créées, d'où viennent les données, et comment explorer l'org.

---

## Table des matières
1. [Les deux niveaux : modèle vs instance](#1-les-deux-niveaux--modèle-vs-instance)
2. [Structure des objets de configuration](#2-structure-des-objets-de-configuration)
3. [Exécution étape par étape — Création des tâches initiales](#3-exécution-étape-par-étape--création-des-tâches-initiales)
4. [Exécution étape par étape — Chaînage par outcome](#4-exécution-étape-par-étape--chaînage-par-outcome)
5. [Les 3 statuts et leur logique](#5-les-3-statuts-et-leur-logique)
6. [Commandes SOQL pour explorer les données](#6-commandes-soql-pour-explorer-les-données)

---

## 1. Les deux niveaux : modèle vs instance

Il faut distinguer deux couches :

```
COUCHE CONFIGURATION (données statiques — configurées par les admins)
┌─────────────────────────────────────────────┐
│  Workflow__c          Workflow_Task__c       │
│  "Réclamation FRA"  → "Lire email"  (SLA 4h)│
│                     → "Appeler client" (8h) │
└─────────────────────────────────────────────┘
                    ↓ les flows utilisent ces modèles pour créer ↓
COUCHE DONNÉES VIVANTES (créées à chaque Case)
┌─────────────────────────────────────────────┐
│  Operational_Task__c                        │
│  "Lire email"    — Case #00012 — Due: 14h   │
│  "Appeler client"— Case #00012 — Due: 22h   │
└─────────────────────────────────────────────┘
```

> **Analogie :** `Workflow_Task__c` est un moule de fabrication. `Operational_Task__c` est la pièce produite avec ce moule pour un Case spécifique.

---

## 2. Structure des objets de configuration

### `Workflow__c` — Le scénario de traitement

Définit quel ensemble de tâches s'applique à quel type de Case, pour quel pays.

| Champ | Type | D'où vient la valeur | Rôle |
|---|---|---|---|
| `Name` | Text | Saisi par l'admin | Nom lisible du workflow |
| `Type__c` | Text | Doit correspondre à `Case.Type` | Type de Case déclencheur |
| `Category__c` | Text | Doit correspondre à `Case.External_Case_Category__c` | Catégorie de Case (optionnel) |
| `Details__c` | Text | Doit correspondre à `Case.External_Case_Detail__c` | Détail de Case (optionnel) |
| `Subsidiary_Indicator__c` | Text | Code filiale (ex: "FRA", "BEL") | Filtre par pays |
| `Business_Hours__c` | Lookup → BusinessHours | ID des heures ouvrées Salesforce | Référence pour le calcul SLA |

**Règle de matching (cascade 3 niveaux) :**
```
Le flow cherche d'abord le plus précis, et s'arrête au premier trouvé :

  Niveau 1 : Type + Category + Details + Subsidiary  ← plus précis
  Niveau 2 : Type + Category + Subsidiary
  Niveau 3 : Type + Subsidiary                        ← plus large
  Aucun trouvé → aucune tâche créée
```

---

### `Workflow_Task__c` — La tâche modèle

Chaque enregistrement représente une étape type dans un workflow.

| Champ | Type | D'où vient la valeur | Rôle |
|---|---|---|---|
| `Name` | Text | Saisi par l'admin | Identifiant interne |
| `Task_Subject__c` | Text | Saisi par l'admin | Sujet affiché sur la tâche créée |
| `Task_Description__c` | Text | Saisi par l'admin | Description pour l'agent |
| `Task_SLA__c` | Number (heures) | Saisi par l'admin | Délai en heures ouvrées |
| `Default_queue_ID__c` | Text | ID d'une Queue Salesforce | Assignataire par défaut |
| `Parent_Workflow__c` | Lookup → Workflow__c | Relation vers le workflow parent | Appartenance au scénario |
| `Is_First_Task__c` | Checkbox | Coché par l'admin | Si true → tâche créée à l'ouverture du Case |
| `Must_be_closed_before_case_can_be_closed__c` | Checkbox (défaut: false) | Configuré par l'admin | Bloque la fermeture du Case |
| `Only_Available_For_Task_Owners__c` | Checkbox (défaut: false) | Configuré par l'admin | Restreint la modification aux propriétaires |
| `Don_t_Restrict_Assignment__c` | Checkbox (défaut: true) | Configuré par l'admin | Contrôle la liste d'assignataires autorisés |
| `Reassign_Task_when_Case_owner_Change__c` | Checkbox (défaut: true) | Configuré par l'admin | Suit les changements de propriétaire du Case |

---

### `Outcome_to_WF_Tasks__c` — Le lien outcome → tâche suivante

Définit quelle(s) tâche(s) créer après la fermeture d'une tâche avec un outcome précis.

| Champ | Rôle |
|---|---|
| `Task_Outcome__c` | Lookup vers l'outcome (résultat de fermeture de tâche) |
| `Workflow_Task__c` | Lookup vers la `Workflow_Task__c` à créer en suivant |

> Un outcome peut déclencher **plusieurs** `Workflow_Task__c` en parallèle.

---

## 3. Exécution étape par étape — Création des tâches initiales

**Déclencheur :** Un Case est créé ou ses champs de qualification changent (`Type`, `External_Case_Category__c`, `External_Case_Detail__c`).

```
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1 — Déclenchement du flow                                     │
│                                                                     │
│  Flow : Flow_Task_Workflow_FirstTask_Creation                       │
│  Type : Record-Triggered After Save sur Case                        │
│                                                                     │
│  Condition d'entrée :                                               │
│  • Case.RecordType.Name doit être dans le Custom Label              │
│    Task_Management_Enabled_Countries_RecordTypes                    │
│  • ET au moins un champ de qualification a changé                   │
│    (ou c'est une création)                                          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2 — Recherche du Workflow__c (cascade 3 niveaux)              │
│                                                                     │
│  Données lues depuis l'objet Case déclencheur :                     │
│  • $Record.Type              → cherché dans Workflow__c.Type__c     │
│  • $Record.External_Case_Category__c → Workflow__c.Category__c     │
│  • $Record.External_Case_Detail__c   → Workflow__c.Details__c      │
│  • $Record.Subsidiary_Indicator__c   → Workflow__c.Subsidiary_     │
│                                         Indicator__c               │
│                                                                     │
│  Requête 1 (la plus précise) :                                      │
│  SELECT Id, Business_Hours__c FROM Workflow__c                      │
│  WHERE Type__c = [Case.Type]                                        │
│    AND Category__c = [Case.Category]                                │
│    AND Details__c = [Case.Details]                                  │
│    AND Subsidiary_Indicator__c = [Case.Subsidiary]                  │
│                                                                     │
│  Si rien trouvé → Requête 2 (sans Details)                          │
│  Si rien trouvé → Requête 3 (sans Category ni Details)              │
│  Si rien trouvé → FIN, aucune tâche créée                           │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3 — Récupération des Workflow_Task__c initiales               │
│                                                                     │
│  Données lues : enregistrements Workflow_Task__c                    │
│                                                                     │
│  Requête :                                                          │
│  SELECT Id, Task_Subject__c, Task_SLA__c, Default_queue_ID__c,      │
│         Must_be_closed_before_case_can_be_closed__c,                │
│         Only_Available_For_Task_Owners__c,                          │
│         Don_t_Restrict_Assignment__c,                               │
│         Reassign_Task_when_Case_owner_Change__c                     │
│  FROM Workflow_Task__c                                              │
│  WHERE Parent_Workflow__c = [ID du Workflow trouvé à l'étape 2]     │
│    AND Is_First_Task__c = true                                      │
│                                                                     │
│  Résultat : une collection de 1 à N tâches modèles                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 4 — Transformation en Operational_Task__c (élément Transform) │
│                                                                     │
│  Pour chaque Workflow_Task__c de la collection :                    │
│                                                                     │
│  Champ Operational_Task__c        ← Source                          │
│  ─────────────────────────────────────────────────────────          │
│  Name (subject)                   ← Workflow_Task__c.Task_Subject__c│
│  Task_SLA__c                      ← Workflow_Task__c.Task_SLA__c    │
│  Case__c                          ← $Record.Id (Case déclencheur)  │
│  Workflow_Task__c                 ← Workflow_Task__c.Id             │
│  Automatic_Task__c                ← true (valeur fixe)             │
│  Subsidiary_Indicator__c          ← $Record.Subsidiary_Indicator__c│
│  Subsidiary__c                    ← $Record.Subsidiary__c          │
│  OwnerId (assignataire)           ← Workflow_Task__c.Default_queue_ │
│                                     ID__c                           │
│  Start_Date__c                    ← $Flow.CurrentDateTime           │
│  Must_be_closed_before_case...    ← Workflow_Task__c.[même champ]  │
│  Only_Available_For_Task_Owners   ← Workflow_Task__c.[même champ]  │
│  Don_t_Restrict_Assignment__c     ← Workflow_Task__c.[même champ]  │
│  Reassign_Task_when_Case_owner... ← Workflow_Task__c.[même champ]  │
│                                                                     │
│  Due_Date__c → calculée à l'étape suivante                          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5 — Calcul de la Due Date (Apex Invocable)                    │
│                                                                     │
│  Pour chaque tâche, appel de l'action Apex :                        │
│  profFlow_bhAdd__addBusinessHours                                   │
│                                                                     │
│  Entrées :                                                          │
│  • businessHoursId      ← Workflow__c.Business_Hours__c             │
│                           (récupéré à l'étape 2)                    │
│  • startDateTime        ← Start_Date__c de la tâche                │
│  • intervalMilliseconds ← Task_SLA__c × 3 600 000                   │
│                           (conversion heures → millisecondes)       │
│                                                                     │
│  Sortie :                                                           │
│  • Due_Date__c ← résultat du calcul (date/heure en heures ouvrées) │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 6 — Création en base                                          │
│                                                                     │
│  Élément : recordCreates                                            │
│  Crée en une seule opération DML toutes les Operational_Task__c     │
│  de la collection                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Exécution étape par étape — Chaînage par outcome

**Déclencheur :** Un agent ferme une tâche via le flow `Flow_Task_Management_Close_Operational_Task`.

```
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1 — L'agent sélectionne un outcome sur l'écran de fermeture   │
│                                                                     │
│  Données affichées :                                                │
│  SELECT Id, Name FROM Task_Outcome__c                               │
│  WHERE Workflow_Task__c = [ID du Workflow_Task__c de la tâche]      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2 — Récupération des tâches suivantes à créer                 │
│                                                                     │
│  SELECT Workflow_Task__c FROM Outcome_to_WF_Tasks__c                │
│  WHERE Task_Outcome__c = [ID de l'outcome sélectionné]              │
│                                                                     │
│  → Peut retourner 0, 1 ou plusieurs Workflow_Task__c                │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3 — Récupération des détails des Workflow_Task__c             │
│                                                                     │
│  SELECT Id, Task_Subject__c, Task_SLA__c, Default_queue_ID__c, ...  │
│  FROM Workflow_Task__c                                              │
│  WHERE Id IN [liste des IDs récupérés à l'étape 2]                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 4 — Même logique que les étapes 4-6 de la création initiale   │
│                                                                     │
│  Transform → Calcul SLA (Apex) → recordCreates                      │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5 — Mise à jour optionnelle du Case                           │
│                                                                     │
│  Si l'outcome a des champs de mise à jour du Case :                 │
│  • Case.Status           ← Outcome.Case_Status__c                   │
│  • Case.Workflow_Step__c ← Outcome.Workflow_Step__c                 │
│  • Case.Reopen_Reason__c ← Outcome.Reopen_Reason__c                 │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 6 — Fermeture de la tâche courante                            │
│                                                                     │
│  Mise à jour de l'Operational_Task__c courante :                    │
│  • Completion_Date__c ← $Flow.CurrentDateTime                       │
│  • Closed_by__c       ← $User.FullName                              │
│  • Task_Outcome__c    ← Nom de l'outcome sélectionné                │
└─────────────────────────────────────────────────────────────────────┘
```

**Schéma de chaînage :**
```
[Case créé]
    │
    ▼
Tâche A  (Is_First_Task = true)
    │
    ├── Outcome "Résolu"    → Tâche B
    │                             │
    │                             └── Outcome "Confirmé" → Tâche D
    │
    └── Outcome "Escaladé"  → Tâche C
                               Tâche E  (en parallèle)
```

> Il n'y a **pas de numéro d'ordre** sur les tâches. L'enchaînement est entièrement défini par les outcomes. Plusieurs tâches peuvent être actives en parallèle sur un même Case.

---

## 5. Les 3 statuts et leur logique

Le statut est une **formule calculée automatiquement** — il n'existe pas de champ "Status" éditable.

```
Status__c =
  SI Completion_Date__c n'est pas vide  → "Completed"
  SINON SI NOW() > Due_Date__c          → "Overdue"
  SINON                                 → "To do"
```

| Statut | Icône | Condition | Ce que ça signifie |
|---|---|---|---|
| `To do` | 🟨 | Pas de Completion_Date + dans les délais | La tâche est ouverte, l'agent doit agir |
| `Overdue` | 🟥 | Pas de Completion_Date + date dépassée | Le SLA est dépassé, tâche en retard |
| `Completed` | ✅ | `Completion_Date__c` est renseignée | Tâche fermée via le flow Close |

**Pour fermer une tâche :** le flow `Close_Operational_Task` renseigne `Completion_Date__c` — c'est la seule façon de passer au statut "Completed".

**Calcul de l'âge :**
```
Age_in_Hours__c =
  SI Completed → (Completion_Date__c - Start_Date__c) × 24
  SINON        → (NOW() - Start_Date__c) × 24
```

---

## 6. Commandes SOQL pour explorer les données

### Prérequis — Connexion à l'org

```bash
# Voir les orgs déjà connectées
sf org list

# Se connecter si besoin (ouvre un navigateur)
sf org login web --alias monAlias
```

> Remplace `<alias>` par ton alias dans toutes les commandes ci-dessous.

---

### Commande 1 — Voir tous les Workflows configurés

```bash
sf data query \
  --query "SELECT Id, Name, Type__c, Category__c, Details__c, Subsidiary_Indicator__c, Business_Hours__r.Name
           FROM Workflow__c
           ORDER BY Subsidiary_Indicator__c, Type__c" \
  --target-org <alias>
```

**Explication de la commande :**

| Partie | Signification |
|---|---|
| `sf data query` | Commande Salesforce CLI pour exécuter une requête SOQL |
| `--query "..."` | La requête SOQL à exécuter |
| `SELECT ... FROM Workflow__c` | Lit les enregistrements de l'objet `Workflow__c` |
| `Business_Hours__r.Name` | Relation de type lookup : `.r` signifie qu'on traverse la relation pour lire le nom des Business Hours liées |
| `ORDER BY Subsidiary_Indicator__c, Type__c` | Trie les résultats par pays puis par type |
| `--target-org <alias>` | Spécifie l'org sur laquelle exécuter la requête |

**Ce que tu vas voir :** La liste de tous les scénarios de traitement configurés, groupés par pays et type de Case.

---

### Commande 2 — Voir les tâches modèles avec leur position dans le workflow

```bash
sf data query \
  --query "SELECT Id, Name, Task_Subject__c, Task_SLA__c, Is_First_Task__c,
                  Must_be_closed_before_case_can_be_closed__c,
                  Don_t_Restrict_Assignment__c,
                  Reassign_Task_when_Case_owner_Change__c,
                  Parent_Workflow__r.Name,
                  Parent_Workflow__r.Type__c,
                  Parent_Workflow__r.Subsidiary_Indicator__c
           FROM Workflow_Task__c
           ORDER BY Parent_Workflow__r.Subsidiary_Indicator__c,
                    Parent_Workflow__r.Name,
                    Is_First_Task__c DESC" \
  --target-org <alias>
```

**Explication de la commande :**

| Partie | Signification |
|---|---|
| `Parent_Workflow__r.Name` | Traverse la relation lookup vers `Workflow__c` pour lire son nom — permet de voir à quel workflow appartient chaque tâche |
| `Is_First_Task__c DESC` | Trie les tâches "première" en tête de liste |
| `Must_be_closed_before_case_can_be_closed__c` | Permet d'identifier les tâches bloquantes |

**Ce que tu vas voir :** Toutes les étapes de chaque workflow, avec leur SLA et leur comportement. Les lignes avec `Is_First_Task__c = true` sont créées automatiquement à l'ouverture d'un Case.

---

### Commande 3 — Voir les chaînes outcome → tâche suivante

```bash
sf data query \
  --query "SELECT Id,
                  Task_Outcome__r.Name,
                  Workflow_Task__r.Task_Subject__c,
                  Workflow_Task__r.Parent_Workflow__r.Name,
                  Workflow_Task__r.Task_SLA__c
           FROM Outcome_to_WF_Tasks__c
           ORDER BY Task_Outcome__r.Name" \
  --target-org <alias>
```

**Explication de la commande :**

| Partie | Signification |
|---|---|
| `Task_Outcome__r.Name` | Nom de l'outcome déclencheur |
| `Workflow_Task__r.Task_Subject__c` | Nom de la tâche qui sera créée après cet outcome |
| `Workflow_Task__r.Parent_Workflow__r.Name` | Double traversée de relation : on remonte jusqu'au workflow parent |

**Ce que tu vas voir :** La carte complète des enchaînements — quel outcome crée quelle(s) tâche(s) suivante(s).

---

### Commande 4 — Voir les tâches réelles sur un Case spécifique

```bash
sf data query \
  --query "SELECT Id, Name, Status__c, Start_Date__c, Due_Date__c,
                  Completion_Date__c, Task_SLA__c, Age_in_Hours__c,
                  Automatic_Task__c, Task_Outcome__c,
                  Workflow_Task__r.Task_Subject__c,
                  Owner.Name
           FROM Operational_Task__c
           WHERE Case__c = '<ID_DU_CASE>'
           ORDER BY Start_Date__c ASC" \
  --target-org <alias>
```

**Explication de la commande :**

| Partie | Signification |
|---|---|
| `WHERE Case__c = '<ID_DU_CASE>'` | Filtre sur un Case précis — remplace par l'ID du Case (commence par `500`) |
| `Workflow_Task__r.Task_Subject__c` | Nom du modèle source (null si tâche manuelle) |
| `Owner.Name` | Nom de l'assignataire (utilisateur ou queue) |
| `ORDER BY Start_Date__c ASC` | Affiche les tâches dans l'ordre chronologique de création |

**Ce que tu vas voir :** L'historique complet des tâches sur un Case, avec leurs statuts et durées réelles.

---

### Commande 5 — Voir les outcomes possibles pour une Workflow_Task

```bash
sf data query \
  --query "SELECT Id, Name, Outcome_will_close_Case__c,
                  Case_Status__c, Workflow_Step__c
           FROM Task_Outcome__c
           WHERE Workflow_Task__c = '<ID_WORKFLOW_TASK>'
           ORDER BY Name" \
  --target-org <alias>
```

**Ce que tu vas voir :** Les choix de fermeture disponibles pour une tâche donnée, et si l'un d'eux ferme le Case.

---

### Résumé — Ordre logique des requêtes pour comprendre un workflow complet

```
1. sf data query sur Workflow__c
        → Identifier le workflow du pays/type qui t'intéresse
        → Récupérer son ID

2. sf data query sur Workflow_Task__c WHERE Parent_Workflow__c = [ID]
        → Voir toutes les étapes du workflow
        → Identifier les premières tâches (Is_First_Task = true)

3. sf data query sur Task_Outcome__c WHERE Workflow_Task__c = [ID tâche]
        → Voir les outcomes possibles pour chaque étape

4. sf data query sur Outcome_to_WF_Tasks__c WHERE Task_Outcome__c = [ID outcome]
        → Voir quelles tâches sont créées après chaque outcome

5. sf data query sur Operational_Task__c WHERE Case__c = [ID Case réel]
        → Vérifier les tâches réelles créées sur un Case existant
```
