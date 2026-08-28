#!/usr/bin/env python3
"""Executable model and source-contract tests for disconnect reconciliation.

The model is deliberately small: it mirrors only the round/task state machine
owned by the deferred reconciliation path. It is not a ReHLDS test double and
does not claim to validate engine integration.
"""

from __future__ import annotations

import itertools
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "src" / "kgb_zombie_escape.sma").read_text(encoding="utf-8")


class ReconciliationModel:
    def __init__(self) -> None:
        self.round_serial = 1
        self.round_active = True
        self.infection_started = True
        self.round_ending = False
        self.scheduled_serial: int | None = None
        self.round_end_calls: list[str] = []
        self.events: list[str] = []

    def schedule_after_disconnect(self) -> None:
        if (
            not self.round_active
            or not self.infection_started
            or self.round_ending
            or self.scheduled_serial is not None
        ):
            return
        self.scheduled_serial = self.round_serial

    def start_new_infected_round(self) -> None:
        self.round_serial += 1
        self.scheduled_serial = None
        self.round_active = True
        self.infection_started = True
        self.round_ending = False

    def reconcile(self, scheduled_serial: int | None, humans: int, zombies: int) -> None:
        if scheduled_serial == self.scheduled_serial:
            self.scheduled_serial = None

        if (
            scheduled_serial != self.round_serial
            or not self.round_active
            or not self.infection_started
            or self.round_ending
        ):
            return

        if humans > 0 and zombies == 0:
            self._end_round("humans")
        elif humans == 0 and zombies > 0:
            self._end_round("zombies")

    def _end_round(self, winner: str) -> None:
        if self.round_ending:
            return
        self.round_ending = True
        self.events.append("round_ending")
        self.round_active = False
        self.events.append("round_inactive")
        self.scheduled_serial = None
        self.events.append("tasks_cancelled")
        self.round_end_calls.append(winner)
        self.events.append("rg_round_end")


class ReconciliationModelTests(unittest.TestCase):
    def test_full_living_role_matrix(self) -> None:
        for humans, zombies in itertools.product(range(3), repeat=2):
            with self.subTest(humans=humans, zombies=zombies):
                model = ReconciliationModel()
                model.schedule_after_disconnect()
                model.reconcile(model.scheduled_serial, humans, zombies)

                expected: list[str]
                if humans > 0 and zombies == 0:
                    expected = ["humans"]
                elif humans == 0 and zombies > 0:
                    expected = ["zombies"]
                else:
                    expected = []
                self.assertEqual(expected, model.round_end_calls)

    def test_duplicate_disconnect_callbacks_coalesce_and_end_once(self) -> None:
        model = ReconciliationModel()
        model.schedule_after_disconnect()
        first_serial = model.scheduled_serial
        model.schedule_after_disconnect()
        self.assertEqual(first_serial, model.scheduled_serial)

        model.reconcile(first_serial, humans=2, zombies=0)
        model.reconcile(first_serial, humans=2, zombies=0)
        self.assertEqual(["humans"], model.round_end_calls)

    def test_new_round_invalidates_stale_callback(self) -> None:
        model = ReconciliationModel()
        model.schedule_after_disconnect()
        stale_serial = model.scheduled_serial
        model.start_new_infected_round()
        model.reconcile(stale_serial, humans=2, zombies=0)
        self.assertEqual([], model.round_end_calls)

    def test_stale_callback_cannot_consume_new_round_task(self) -> None:
        model = ReconciliationModel()
        model.schedule_after_disconnect()
        stale_serial = model.scheduled_serial
        model.start_new_infected_round()
        model.schedule_after_disconnect()
        current_serial = model.scheduled_serial

        model.reconcile(stale_serial, humans=2, zombies=0)
        self.assertEqual(current_serial, model.scheduled_serial)
        self.assertEqual([], model.round_end_calls)

    def test_admin_replacement_infection_wins_race(self) -> None:
        model = ReconciliationModel()
        model.schedule_after_disconnect()
        # An admin infects a replacement before the deferred callback runs.
        model.reconcile(model.scheduled_serial, humans=1, zombies=1)
        self.assertEqual([], model.round_end_calls)

    def test_inactive_waiting_or_ending_rounds_do_not_schedule(self) -> None:
        for active, infected, ending in (
            (False, True, False),
            (True, False, False),
            (True, True, True),
        ):
            with self.subTest(active=active, infected=infected, ending=ending):
                model = ReconciliationModel()
                model.round_active = active
                model.infection_started = infected
                model.round_ending = ending
                model.schedule_after_disconnect()
                model.reconcile(model.scheduled_serial, humans=2, zombies=0)
                self.assertEqual([], model.round_end_calls)

    def test_state_and_task_cancellation_precede_engine_round_end(self) -> None:
        model = ReconciliationModel()
        model.schedule_after_disconnect()
        model.reconcile(model.scheduled_serial, humans=1, zombies=0)
        self.assertEqual(
            ["round_ending", "round_inactive", "tasks_cancelled", "rg_round_end"],
            model.events,
        )


def function_body(name: str) -> str:
    match = re.search(rf"(?:public|stock)\s+{re.escape(name)}\([^)]*\)\s*\{{", SOURCE)
    if match is None:
        raise AssertionError(f"missing Pawn function: {name}")

    brace_depth = 1
    cursor = match.end()
    while cursor < len(SOURCE) and brace_depth:
        if SOURCE[cursor] == "{":
            brace_depth += 1
        elif SOURCE[cursor] == "}":
            brace_depth -= 1
        cursor += 1
    if brace_depth:
        raise AssertionError(f"unterminated Pawn function: {name}")
    return SOURCE[match.end() : cursor - 1]


class PawnSourceContractTests(unittest.TestCase):
    def test_disconnect_defers_instead_of_counting_departing_slot(self) -> None:
        body = function_body("client_disconnect")
        self.assertIn("schedule_role_reconciliation()", body)
        self.assertNotIn("check_remaining_humans()", body)

    def test_reconciliation_is_round_bound_and_has_both_terminal_paths(self) -> None:
        body = function_body("reconcile_roles_deferred")
        self.assertIn("scheduled_round_serial != g_round_serial", body)
        self.assertIn("humans > 0 && zombies == 0", body)
        self.assertIn("humans == 0 && zombies > 0", body)
        self.assertIn("end_round_for_humans()", body)
        self.assertIn("end_round_for_zombies()", body)

    def test_disconnect_callbacks_coalesce(self) -> None:
        body = function_body("schedule_role_reconciliation")
        self.assertIn("g_reconcile_task_id != 0", body)
        self.assertIn("TASK_RECONCILE_BASE + g_round_serial", body)
        self.assertEqual(1, body.count("set_task("))

    def test_round_reset_cancels_reconciliation_and_advances_generation(self) -> None:
        self.assertIn("g_round_serial++", function_body("on_new_round"))
        cancel_body = function_body("cancel_round_tasks")
        self.assertIn("remove_task(g_reconcile_task_id)", cancel_body)
        self.assertIn("g_reconcile_task_id = 0", cancel_body)

    def test_terminal_helpers_update_state_and_cancel_before_reapi(self) -> None:
        for name, expected_native in (
            (
                "end_round_for_humans",
                "rg_round_end(1.0, WINSTATUS_CTS, ROUND_CTS_WIN)",
            ),
            (
                "end_round_for_zombies",
                "rg_round_end(1.0, WINSTATUS_TERRORISTS, ROUND_TERRORISTS_WIN)",
            ),
        ):
            with self.subTest(name=name):
                body = function_body(name)
                ending = body.index("g_round_ending = true")
                inactive = body.index("g_round_active = false")
                cancel = body.index("cancel_round_tasks()")
                engine_end = body.index(expected_native)
                self.assertLess(ending, inactive)
                self.assertLess(inactive, cancel)
                self.assertLess(cancel, engine_end)


if __name__ == "__main__":
    unittest.main(verbosity=2)
