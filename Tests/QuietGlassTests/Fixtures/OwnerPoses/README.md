# Owner pose regression fixtures

Three frames of the same generated fictional actor: center (0.0s), own left (1.6s), and own right (3.4s). Source: QuietGlass launch-film owner-front motion footage, generated with Veo 3.1. Resized to 640 × 360. No user camera images or biometric templates are included.

These fixtures exercise the real Vision detection → landmarks → SFace feature path and the turn-step transitions. They catch the landmark-only detector returning coarse yaw values and the enrollment policy incorrectly discarding valid head turns. Synthetic policy tests separately check required ordering, wrong directions, unknown faces and missing frames.
