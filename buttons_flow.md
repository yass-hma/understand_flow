# Buttons Flow — Conditions des boutons du tableau de bord
> Analyse exacte des conditions de visibilité et d'activation de chaque bouton dans `Flow_Task_Management_Display_Progress`.

---

## Table des matières
1. [Vue d'ensemble de l'écran](#1-vue-densemble-de-lécran)
2. [Mécanisme de vérification des droits](#2-mécanisme-de-vérification-des-droits)
3. [Bouton : Create Task](#3-bouton--create-task)
4. [Bouton : Assign to me](#4-bouton--assign-to-me)
5. [Bouton : Assign to](#5-bouton--assign-to)
6. [Bouton : Close Task](#6-bouton--close-task)
7. [Messages d'information conditionnels](#7-messages-dinformation-conditionnels)
8. [Auto-refresh après action](#8-auto-refresh-après-action)
9. [Tableau récapitulatif des conditions](#9-tableau-récapitulatif-des-conditions)
10. [Formules de désactivation définies dans le flow](#10-formules-de-désactivation-définies-dans-le-flow)

---

## 1. Vue d'ensemble de l'écran

Le tableau de bord est un **Screen Flow** embarqué sur la page Case. Il affiche toutes les `Operational_Task__c` du Case dans un datatable, et expose 4 boutons d'action.

**Structure de l'écran :**
```
┌─────────────────────────────────────────────────────────┐
│  ⚙ Operational Tasks                  [Create Task]     │
├─────────────────────────────────────────────────────────┤
│  Datatable (sélection unique)                            │
│  ┌──────────┬────┬────────┬───────────┬────────┬──────┐ │
│  │ Task     │Icon│ Status │ Start Date│Due Date│Owner │ │
│  └──────────┴────┴────────┴───────────┴────────┴──────┘ │
├─────────────────────────────────────────────────────────┤
│  🚫 [Message si tâche fermée ou accès refusé]           │
├─────────────────────────────────────────────────────────┤
│  [Assign to me]   [Assign to]   [Close Task]            │
└─────────────────────────────────────────────────────────┘
```

**Colonnes du datatable :**
| Colonne | Champ API | Type |
|---|---|---|
| Task | `Task_Name__c` (lien cliquable) | customRichText |
| Icône | `Status_Icon__c` (🟨/🟥/✅) | customRichText |
| Status | `Status__c` | customRichText |
| Start Date | `Start_Date__c` | customDateTime |
| Due Date | `Due_Date__c` | customDateTime |
| Owner | `Owner__c` | customRichText |
| Completion Date | `Completion_Date__c` | customDateTime |
| Task Outcome | `Task_Outcome__c` | text |

> Le datatable est en **sélection unique** (`SINGLE_SELECT`). Les boutons d'action réagissent à la ligne sélectionnée (`firstSelectedRow`).

---

## 2. Mécanisme de vérification des droits

Avant que les boutons soient actifs, un flow de vérification s'exécute automatiquement.

### Déclenchement
La Screen Action `Action_screen_verify_userAllowed` est appelée à **deux moments** :
1. À l'**initialisation** de l'écran (`flow__screeninit`)
2. À **chaque changement** dans le datatable (`flow__screenfieldattributechange`)

```
Utilisateur sélectionne une tâche dans le tableau
         ↓
Screen Action : Flow_Task_Management_Verify_if_user_is_allowed_to_modify_Op_Task
  Input  → recordId = firstSelectedRow.Id
  Output → Allowed_To_Modify (Boolean)
         ↓
Les boutons lisent ce résultat pour leur condition de visibilité
```

### Ce que retourne la vérification

| `Allowed_To_Modify` | Signification |
|---|---|
| `true` | L'utilisateur peut modifier la tâche → boutons visibles |
| `false` | L'utilisateur n'a pas les droits → boutons masqués + message d'erreur affiché |

### Pendant la vérification
`Action_screen_verify_userAllowed.InProgress = true` pendant l'exécution.
Les formules de désactivation utilisent ce flag pour éviter tout clic pendant le calcul.

---

## 3. Bouton : Create Task

**Label :** `Create Task`
**Style :** `brand-outline` (bleu contour)
**Flow lancé :** `Flow_Task_Management_Create_Manual_Task`
**Input passé :** `recordId` = ID du **Case** (pas de la tâche)

### Condition de visibilité (visibilityRule)

```
Le bouton est VISIBLE si :
  firstSelectedRow.Id IS NOT NULL
  (= il y a au moins une tâche dans le tableau et elle est sélectionnée)
```

> Le datatable est pré-configuré avec `selectedRows = Get_ALL_Operational_Tasks`, donc la première tâche de la liste est automatiquement sélectionnée au chargement.

### Comportement
- **Pas de condition de droits** : n'importe quel utilisateur peut créer une tâche manuelle
- **Pas de condition sur le statut** de la tâche sélectionnée
- La modal s'ouvre avec le contexte du **Case** (pas de la tâche sélectionnée)

### Ce qui se passe après
Si le flow se termine avec `OUTPUT_String = "SUCCESS"` → rafraîchissement automatique du tableau.

---

## 4. Bouton : Assign to me

**Label :** `Assign to me`
**Style :** `success` (vert)
**Flow lancé :** `Flow_Task_Management_Assign_Task_to_running_User`
**Input passé :** `recordId` = ID de la **tâche sélectionnée**

### Condition de visibilité (visibilityRule) — TOUTES les conditions doivent être vraies

```
Le bouton est VISIBLE si :
  1. firstSelectedRow.Id IS NOT NULL
     → une tâche est sélectionnée dans le tableau

  2. firstSelectedRow.Status__c != "Completed"
     → la tâche n'est pas déjà fermée

  3. Action_screen_verify_userAllowed.Results.Allowed_To_Modify = true
     → l'utilisateur a les droits de modifier la tâche

  4. firstSelectedRow.OwnerId != $User.Id
     → l'utilisateur n'est PAS déjà le propriétaire de la tâche
```

### Logique de la condition 4 (OwnerId ≠ User)
Si l'utilisateur est **déjà propriétaire** de la tâche, le bouton "Assign to me" est inutile et donc masqué. Cela évite une réassignation redondante.

### Formule de désactivation associée (`DisableButtonAssign2me`)
```
ISBLANK(firstSelectedRow.Id)
  || Status__c = "Completed"
  || Action_screen_verify_userAllowed.InProgress = true
  || Allowed_To_Modify = false
  || OwnerId = $User.Id
```
> Cette formule couvre les mêmes cas que la visibilityRule, avec en plus le cas `InProgress = true` (vérification des droits en cours).

---

## 5. Bouton : Assign to

**Label :** `Assign to`
**Style :** `brand` (bleu plein)
**Flow lancé :** `Flow_Task_Management_Assign_Task_to_another_User`
**Input passé :** `recordId` = ID de la **tâche sélectionnée**

### Condition de visibilité (visibilityRule) — TOUTES les conditions doivent être vraies

```
Le bouton est VISIBLE si :
  1. firstSelectedRow.Id IS NOT NULL
     → une tâche est sélectionnée dans le tableau

  2. firstSelectedRow.Status__c != "Completed"
     → la tâche n'est pas déjà fermée

  3. Action_screen_verify_userAllowed.Results.Allowed_To_Modify = true
     → l'utilisateur a les droits de modifier la tâche
```

### Différence avec "Assign to me"
Le bouton "Assign to" **n'a pas de condition sur l'OwnerId**. Un superviseur peut réassigner une tâche dont il est déjà propriétaire à quelqu'un d'autre.

### Formule de désactivation associée (`DisableButtonAssigntouser`)
```
ISBLANK(firstSelectedRow.Id)
  || Status__c = "Completed"
  || Action_screen_verify_userAllowed.InProgress = true
  || Allowed_To_Modify = false
```

---

## 6. Bouton : Close Task

**Label :** `Close Task`
**Style :** `destructive-text` (rouge texte)
**Flow lancé :** `Flow_Task_Management_Close_Operational_Task`
**Input passé :** `recordId` = ID de la **tâche sélectionnée**

### Condition de visibilité (visibilityRule) — TOUTES les conditions doivent être vraies

```
Le bouton est VISIBLE si :
  1. firstSelectedRow.Id IS NOT NULL
     → une tâche est sélectionnée dans le tableau

  2. firstSelectedRow.Status__c != "Completed"
     → la tâche n'est pas déjà fermée

  3. Action_screen_verify_userAllowed.Results.Allowed_To_Modify = true
     → l'utilisateur a les droits de modifier la tâche
```

> Les conditions de "Close Task" sont **identiques** à celles de "Assign to". Les deux boutons sont visibles ou masqués ensemble.

### Particularité
Le flow `Close_Operational_Task` ajoute une vérification supplémentaire **à l'intérieur du flow** : si la tâche a le flag `Must_be_closed_before_case_can_be_closed__c` et que d'autres tâches bloquantes sont encore ouvertes, la fermeture est bloquée avec un message d'erreur à l'intérieur de la modal.

---

## 7. Messages d'information conditionnels

L'écran affiche des messages contextuels selon l'état de la tâche sélectionnée.

### Message 1 — Tâche fermée

**Texte :** `🚫 Selected task is closed and can't be modified or reassigned`
**Couleur :** Rouge

**Condition d'affichage :**
```
firstSelectedRow.Status__c = "Completed"
  ET Case.Status != "Closed"
```

> Le message n'apparaît pas si le Case lui-même est fermé (les boutons disparaissent de toute façon).

---

### Message 2 — Modification non autorisée

**Texte :** `🚫 You are not allowed to modify this task. Please contact the task current owner.`
**Couleur :** Rouge

**Condition d'affichage :**
```
Action_screen_verify_userAllowed.Results.Allowed_To_Modify = false
  ET firstSelectedRow.Status__c != "Completed"
```

> Ce message apparaît uniquement quand la tâche est ouverte **mais** que l'utilisateur n'a pas les droits. Si la tâche est déjà fermée, c'est le message 1 qui s'affiche à la place.

---

## 8. Auto-refresh après action

Après qu'un bouton a été utilisé avec succès, l'écran se rafraîchit automatiquement via le composant `c:ers_AutoNavigate_Refresh`.

**Condition de déclenchement (logique OR) :**
```
Button_close_Task.OUTPUT_String   = "SUCCESS"
  OU Button_assign2User.OUTPUT_String = "SUCCESS"
  OU Button_assign2me.OUTPUT_String   = "SUCCESS"
  OU Button_Create_Task.OUTPUT_String = "SUCCESS"
```

> Chaque flow enfant retourne `OUTPUT_String = "SUCCESS"` quand il se termine correctement. Cela permet au tableau de bord de recharger les données sans que l'utilisateur ne clique sur "Refresh".

---

## 9. Tableau récapitulatif des conditions

| Condition | Create Task | Assign to me | Assign to | Close Task |
|---|:---:|:---:|:---:|:---:|
| Une tâche est sélectionnée (`Id IS NOT NULL`) | ✅ | ✅ | ✅ | ✅ |
| Tâche non complétée (`Status != "Completed"`) | — | ✅ | ✅ | ✅ |
| Utilisateur autorisé (`Allowed_To_Modify = true`) | — | ✅ | ✅ | ✅ |
| Utilisateur n'est pas déjà propriétaire | — | ✅ | — | — |

**Lecture :** ✅ = condition requise / — = non vérifiée pour ce bouton

---

### Schéma décisionnel par scénario

| Scénario | Create Task | Assign to me | Assign to | Close Task |
|---|:---:|:---:|:---:|:---:|
| Aucune tâche dans le tableau | ❌ | ❌ | ❌ | ❌ |
| Tâche sélectionnée, statut "Completed" | ✅ | ❌ | ❌ | ❌ |
| Tâche sélectionnée, utilisateur non autorisé | ✅ | ❌ | ❌ | ❌ |
| Tâche sélectionnée, utilisateur déjà propriétaire | ✅ | ❌ | ✅ | ✅ |
| Tâche sélectionnée, utilisateur autorisé, pas propriétaire | ✅ | ✅ | ✅ | ✅ |

---

## 10. Formules de désactivation définies dans le flow

Deux formules Boolean sont définies dans le flow. Elles capturent la logique de désactivation de manière centralisée.

### `DisableButtonAssign2me`
```
ISBLANK({!DataTabeOperationalTasks.firstSelectedRow.Id})
  || {!DataTabeOperationalTasks.firstSelectedRow.Status__c} = "Completed"
  || {!Action_screen_verify_userAllowed.InProgress} = true
  || {!Action_screen_verify_userAllowed.Results.Allowed_To_Modify} = false
  || {!DataTabeOperationalTasks.firstSelectedRow.OwnerId} = {!$User.Id}
```

| Condition | Signification métier |
|---|---|
| `ISBLANK(Id)` | Aucune tâche sélectionnée |
| `Status = "Completed"` | La tâche est déjà fermée |
| `InProgress = true` | La vérification des droits est en cours |
| `Allowed_To_Modify = false` | L'utilisateur n'a pas les droits |
| `OwnerId = $User.Id` | L'utilisateur est déjà propriétaire |

---

### `DisableButtonAssigntouser`
```
ISBLANK({!DataTabeOperationalTasks.firstSelectedRow.Id})
  || {!DataTabeOperationalTasks.firstSelectedRow.Status__c} = "Completed"
  || {!Action_screen_verify_userAllowed.InProgress} = true
  || {!Action_screen_verify_userAllowed.Results.Allowed_To_Modify} = false
```

> Identique à `DisableButtonAssign2me` **sans** la condition sur l'OwnerId — un superviseur peut réassigner même s'il est déjà propriétaire.
