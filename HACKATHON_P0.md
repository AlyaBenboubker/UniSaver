# P0 — livraison et test, 12 octobre 2026

## Vérifications

- Suite complète unitaire exécutée : 91 tests passent, 7 échouent. Les neuf tests `TaskWorkspaceTests` passent dans le contrôle ciblé final. Pas de baseline propre disponible : les échecs des tests existants ne sont pas présentés comme prouvés antérieurs aux changements.
- Échecs : `icsParserUsesExplicitFloatingSourceTimeZone`, `resourceImportValidationReturnsExplicitErrors`, `gamificationCountsOneActiveDayForMultipleActivities`, `gamificationComebackUsesSmallExistingActionWithoutBonusXP`, `conversationAvailabilityCreatesReviewableWorkSessionWithoutInventingRecurringPreference`, `conversationFixtureExtractsStructuredActionsWithMadridDates`, `currentSchemaUsesCurrentAppWorkspaceModel`.
- Tests ciblés : lecture du ledger ancien, consentement des notes, corrections/idempotence, import sans date/critères inventés, dates de soumission distinctes, sessions désélectionnées, chrono sans completion et récompenses sans doublon, vraie fermeture/réouverture d'un store temporaire avec notes/checklist/bilan/justificatif.
- Vérification UI via `TaskWorkspaceUITests` sur bundle explicite `alyaben.UniSaver` et fixture isolée. Le dernier lancement échoue parce que XCTest ne peut pas terminer l’instance ouverte `alyaben.UniSaver` (PID 3478). Pas de fermeture forcée ni de preuve UI finale.
- Build macOS final réussi; 25 tests ciblés passent le 13 octobre.
- Appel AI réel validé le 13 octobre sur fixture synthétique : OpenAI gpt-4o-mini, conseil pour 40 minutes et création typée du bon cours/demain avec réponse après enregistrement. Aucun parcours complet A–H avec une vraie consigne étudiant réalisé. Voir AGENT_BEHAVIOUR_REPAIR.md. iPad, Dark Mode, Dynamic Type, Reduce Motion et lecture VoiceOver ne sont pas validés par cette session.

Commandes depuis ce dossier :

```sh
xcodebuild -project UniSaver.xcodeproj -scheme UniSaver -destination 'platform=macOS' build
xcodebuild -project UniSaver.xcodeproj -scheme UniSaver -destination 'platform=macOS' -only-testing:UniSaverTests/TaskWorkspaceTests -only-testing:UniSaverUITests/TaskWorkspaceUITests test
```

## Démonstration — trois minutes

Préparer un devoir réel non confidentiel, un provider déjà configuré/testé dans Settings et une matière vide. Prévoir une date explicite; à défaut, conserver « aucune deadline ». Ne pas utiliser le mode démo comme preuve AI.

1. **0:00–0:45** Classes → matière → Add assignment. Importer PDF/texte ou coller la consigne; ouvrir l'original. Corriger titre, livrables, critères, deadline et vérifier les références. Marquer les exigences comme reviewed.
2. **0:45–1:15** Relire les quatre actions génériques; adapter production et condition de fin au devoir. Garder la soumission séparée. Vérifier les estimations et laisser les créneaux décochés si on ne veut pas les confirmer.
3. **1:15–2:10** Confirmer → jalon → Start task. Ouvrir la ressource, écrire une tentative dans les notes. Ouvrir le panneau contextualisé; demander un indice, puis coller une tentative pour la vérifier. Montrer le consentement de partage des notes et les sources. Si l'AI échoue, montrer le message et poursuivre manuellement.
4. **2:10–3:00** Cocher une étape → Continue later. Renseigner travail restant et justificatif facultatif; Save progress. Reprendre la tâche ou relancer l'app : montrer notes, checklist, ressources et bilan. Distinguer fin de session et devoir entièrement terminé. Ne pas annoncer une soumission confirmée par API.

## Checklist étudiant — test indépendant

- [ ] A. Importer son vrai devoir et retrouver l'original; relever les champs absents et références erronées.
- [ ] B. Corriger et approuver les exigences/actions sans assistance du présentateur.
- [ ] C. Trouver la prochaine étape et sa condition de fin; démarrer.
- [ ] D. Ouvrir une ressource; écrire une note; passer dans une autre application puis revenir.
- [ ] E. Demander un indice puis vérifier une tentative; juger le feedback contre un corrigé fiable s'il existe. Tester notes non partagées/partagées, annulation, AI non configurée et réseau indisponible.
- [ ] F. Enregistrer un bilan, ce qui reste et un justificatif. Tester fin de session séparément de fin de devoir.
- [ ] G. Quitter/relancer; vérifier notes, sources, conversation, étapes et bilan.
- [ ] H. Répéter l'ouverture/la sauvegarde; vérifier absence de doublons tâches, sessions et XP. Retenter un import identique.
- [ ] Relever temps réel facultatif, blocages et endroits où l'étudiant demande une aide humaine. Ne pas enregistrer automatiquement le contenu privé des documents.
- [ ] Vérifier fenêtre étroite, PDF scanné, fichier absent, sauvegarde impossible et restauration après erreur.

Critère de réussite de l'hypothèse : l'étudiant transforme sa vraie consigne en prochaine action et réalise une session sans accompagnement. La réussite de cette hypothèse n'est pas affirmée ici.
