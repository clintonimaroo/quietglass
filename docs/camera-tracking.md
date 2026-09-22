# ADR: Camera tracking and nearby attention

Status: Accepted. Date: 2026-09-22.

Camera and AirPods remain explicit choices. Camera frames stay in memory on the Mac. A shared capture feed supplies camera head tracking and Nearby people; enrollment and coverage testing suspend head tracking and use their existing preview sessions. This avoids independent production sessions contending for one camera.

Camera calibration requires one steady face with valid yaw and pitch for 1.2 seconds. Turns need 0.3 seconds, returns 0.4 seconds, and missing/stale poses cover after 0.65 seconds. Short geometric tracks stabilize selection but do not establish identity. Optional Recognize me remains a separate condition for clearing protection.

Nearby people can use Facing screen or Any extra face. Facing screen tracks each face separately, requiring 0.7 seconds of estimated forward orientation; missing angles use a conservative 1.2-second delay. It does not estimate eye gaze or prove someone is reading a display. Without recognition, a single face or a clearly dominant central face establishes the working-person track; ambiguous crowds stay conservative. Saved-owner matching remains required when enabled, including with multiple faces in view.

Alternatives considered: separate camera sessions (simpler ownership, duplicated work and device conflicts); feeding only raw face counts (current behavior, cannot distinguish sustained attention); treating missing angles as safe (rejected because it could suppress protection).

Consequences: more analysis than count-only detection, conservative alerts for unreadable faces, and remaining need for real crowded-scene and battery measurements. Geometry tracks cannot reliably distinguish identity swaps or every crossing; recognition and the strict option remain available.
