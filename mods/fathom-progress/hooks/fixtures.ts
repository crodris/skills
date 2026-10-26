// Captured from bd version 1.1.0 (Homebrew) by scripts/seed-fathom-fixture.sh. Do not edit:
// run the script again. Real bd output, so ids and times differ between runs; the
// tests lean on the shape, not on the values.
//
// One Fathom run (SLU-123, five chained tasks) at each stage, then a second run
// (SLU-124) started while the first one's epic is still listed. Each stage holds what
// the mod reads: every epic, then the run's tasks, its ready tasks, its counts by
// status and its in-progress task.

import type { Run } from './bd'

export const idle = {
  epics: [],
  tasks: [],
  ready: [],
  counts: {
    "groups": [],
    "schema_version": 1,
    "total": 0
  },
  inProgress: [],
} as const

export const epicOnly = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [],
  ready: [],
  counts: {
    "groups": [],
    "schema_version": 1,
    "total": 0
  },
  inProgress: [],
} as const

export const created1 = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  ready: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  counts: {
    "groups": [
      {
        "count": 1,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 1
  },
  inProgress: [],
} as const

export const created3 = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:00Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:20:59Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  ready: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  counts: {
    "groups": [
      {
        "count": 3,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 3
  },
  inProgress: [],
} as const

export const created5 = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:04Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:03Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:00Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:20:59Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  ready: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  counts: {
    "groups": [
      {
        "count": 5,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [],
} as const

export const nextReady = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:04Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:03Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:00Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:20:59Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  ready: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:20:56Z"
    }
  ],
  counts: {
    "groups": [
      {
        "count": 5,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [],
} as const

export const claimedFirst = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:04Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:03Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:00Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:20:59Z"
    },
    {
      "assignee": "fixture",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:10Z",
      "status": "in_progress",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:21:10Z"
    }
  ],
  ready: [],
  counts: {
    "groups": [
      {
        "count": 1,
        "group": "in_progress"
      },
      {
        "count": 4,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [
    {
      "assignee": "fixture",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:10Z",
      "status": "in_progress",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:21:10Z"
    }
  ],
} as const

export const claimedThird = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:04Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:03Z"
    },
    {
      "assignee": "fixture",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:14Z",
      "status": "in_progress",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:14Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:13Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:13Z",
      "status": "closed",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:21:13Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:12Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:10Z",
      "status": "closed",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:21:12Z"
    }
  ],
  ready: [],
  counts: {
    "groups": [
      {
        "count": 2,
        "group": "closed"
      },
      {
        "count": 1,
        "group": "in_progress"
      },
      {
        "count": 2,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [
    {
      "assignee": "fixture",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:14Z",
      "status": "in_progress",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:14Z"
    }
  ],
} as const

export const allClosed = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:20:54Z"
    }
  ],
  tasks: [
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:19Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:18Z",
      "status": "closed",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:19Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:18Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:17Z",
      "status": "closed",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:18Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:17Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:14Z",
      "status": "closed",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:17Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:13Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:13Z",
      "status": "closed",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:21:13Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:12Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:10Z",
      "status": "closed",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:21:12Z"
    }
  ],
  ready: [],
  counts: {
    "groups": [
      {
        "count": 5,
        "group": "closed"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [],
} as const

export const finished = {
  epics: [
    {
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:22Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "closed",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:21:22Z"
    }
  ],
  tasks: [
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:19Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:04Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:03Z",
          "created_by": "fixture",
          "depends_on_id": "fx-9kf",
          "issue_id": "fx-8vy",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 5 of 5.",
      "external_ref": "SLU-123-5",
      "id": "fx-8vy",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:18Z",
      "status": "closed",
      "title": "SLU-123: Verify in a live session",
      "updated_at": "2026-10-09T10:21:19Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:18Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:03Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:02Z",
          "created_by": "fixture",
          "depends_on_id": "fx-avr",
          "issue_id": "fx-9kf",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 4 of 5.",
      "external_ref": "SLU-123-4",
      "id": "fx-9kf",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:17Z",
      "status": "closed",
      "title": "SLU-123: Draw the executing view",
      "updated_at": "2026-10-09T10:21:18Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:17Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:00Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:00Z",
          "created_by": "fixture",
          "depends_on_id": "fx-dlb",
          "issue_id": "fx-avr",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 3 of 5.",
      "external_ref": "SLU-123-3",
      "id": "fx-avr",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:14Z",
      "status": "closed",
      "title": "SLU-123: Wire the lifecycle hooks",
      "updated_at": "2026-10-09T10:21:17Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:13Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:59Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:20:59Z",
          "created_by": "fixture",
          "depends_on_id": "fx-yf3",
          "issue_id": "fx-dlb",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 1,
      "description": "Sub-task 2 of 5.",
      "external_ref": "SLU-123-2",
      "id": "fx-dlb",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:13Z",
      "status": "closed",
      "title": "SLU-123: Capture the fixtures",
      "updated_at": "2026-10-09T10:21:13Z"
    },
    {
      "assignee": "fixture",
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:12Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:56Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 5.",
      "external_ref": "SLU-123-1",
      "id": "fx-yf3",
      "issue_type": "task",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "started_at": "2026-10-09T10:21:10Z",
      "status": "closed",
      "title": "SLU-123: Draft the plan doc",
      "updated_at": "2026-10-09T10:21:12Z"
    }
  ],
  ready: [],
  counts: {
    "groups": [
      {
        "count": 5,
        "group": "closed"
      }
    ],
    "schema_version": 1,
    "total": 5
  },
  inProgress: [],
} as const

export const stacked = {
  epics: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:25Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-124",
      "id": "fx-4qx",
      "issue_type": "epic",
      "labels": [
        "SLU-124"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "open",
      "title": "SLU-124",
      "updated_at": "2026-10-09T10:21:25Z"
    },
    {
      "close_reason": "Closed",
      "closed_at": "2026-10-09T10:21:22Z",
      "comment_count": 0,
      "created_at": "2026-10-09T10:20:54Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 0,
      "external_ref": "SLU-123",
      "id": "fx-1yo",
      "issue_type": "epic",
      "labels": [
        "SLU-123"
      ],
      "owner": "fixture@example.com",
      "priority": 1,
      "status": "closed",
      "title": "SLU-123",
      "updated_at": "2026-10-09T10:21:22Z"
    }
  ],
  tasks: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:26Z",
      "created_by": "fixture",
      "dependencies": [
        {
          "created_at": "2026-10-09T00:21:26Z",
          "created_by": "fixture",
          "depends_on_id": "fx-8a6",
          "issue_id": "fx-65v",
          "metadata": "{}",
          "type": "blocks"
        }
      ],
      "dependency_count": 1,
      "dependent_count": 0,
      "description": "Sub-task 2 of 2.",
      "external_ref": "SLU-124-2",
      "id": "fx-65v",
      "issue_type": "task",
      "labels": [
        "SLU-124"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-124: Document the retry",
      "updated_at": "2026-10-09T10:21:26Z"
    },
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:25Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 2.",
      "external_ref": "SLU-124-1",
      "id": "fx-8a6",
      "issue_type": "task",
      "labels": [
        "SLU-124"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-124: Add the retry",
      "updated_at": "2026-10-09T10:21:25Z"
    }
  ],
  ready: [
    {
      "comment_count": 0,
      "created_at": "2026-10-09T10:21:25Z",
      "created_by": "fixture",
      "dependency_count": 0,
      "dependent_count": 1,
      "description": "Sub-task 1 of 2.",
      "external_ref": "SLU-124-1",
      "id": "fx-8a6",
      "issue_type": "task",
      "labels": [
        "SLU-124"
      ],
      "owner": "fixture@example.com",
      "priority": 2,
      "status": "open",
      "title": "SLU-124: Add the retry",
      "updated_at": "2026-10-09T10:21:25Z"
    }
  ],
  counts: {
    "groups": [
      {
        "count": 2,
        "group": "open"
      }
    ],
    "schema_version": 1,
    "total": 2
  },
  inProgress: [],
} as const

// The adapter's parent edge, which bd 1.1.0 refuses.
export const epicEdge: Run = {
  exitCode: 1,
  stdout: "",
  stderr: "Error: epics can only block other epics, not tasks\n",
}

// bd run where no .beads directory is reachable. The error is on stderr even with --json.
export const noWorkspace: Run = {
  exitCode: 1,
  stdout: "",
  stderr: "Error: no beads database found\nHint: run 'bd where' to inspect the resolved workspace, or 'bd init' to create a new database\n      or set BEADS_DIR to point to your .beads directory\n",
}

// The human output, for a caller that forgot --json.
export const notJson: Run = {
  exitCode: 0,
  stdout: "✓ fx-8vy ● P2 task SLU-123: Verify in a live session\n✓ fx-9kf ● P2 task SLU-123: Draw the executing view\n✓ fx-avr ● P2 task SLU-123: Wire the lifecycle hooks\n✓ fx-dlb ● P2 task SLU-123: Capture the fixtures\n✓ fx-yf3 ● P2 task SLU-123: Draft the plan doc\n\n--------------------------------------------------------------------------------\nTotal: 5 issues (0 open, 0 in progress)\n\nStatus: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n",
  stderr: "",
}

