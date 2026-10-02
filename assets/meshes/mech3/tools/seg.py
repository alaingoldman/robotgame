"""Part labelling for mech3 (studs, model space: +X = mech right, front = -Z, feet y=0).
Cut values were read from gridded renders + cross-sections of the scaled mesh (tools/grid_views.py, tools/slices.py).
Z values below are BEFORE the depth boost (build.py multiplies z by ZS after labelling-space transform)."""
import numpy as np

P = dict(
    neck_y=17.45, neck_block_y=17.05,
    pad_y=16.15, pad_x=1.85,
    arm_x=1.9, elbow_y=13.85, forearm_x=2.75, wrist_y=10.85, hand_x=3.0,
    waist_y=12.4, hip_y=11.6, crotch_x=0.6, crotch_bot=10.0, thigh_plate_x=1.65, thigh_plate_y=12.0,
    knee_y=7.2, ankle_y=1.55,
)


def label_points(p, wing=None):
    """p: Nx3 points in model space (z in UN-boosted units). wing: optional bool mask (component-based, already sided by x)."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    lab = np.full(len(p), 'Torso', dtype=object)

    def setm(m, name, sided=True):
        if sided:
            lab[m & (x >= 0)] = name + '_R'
            lab[m & (x < 0)] = name + '_L'
        else:
            lab[m] = name

    # ---- legs / pelvis
    leg = ((y < P['hip_y']) & (ax > P['crotch_x'])) | (y < P['crotch_bot'])
    leg |= (y < P['thigh_plate_y']) & (ax > P['thigh_plate_x']) & (ax < 2.7)   # blue thigh-plate tips
    setm(leg & (y >= P['knee_y']), 'Thigh')
    setm(leg & (y < P['knee_y']) & (y >= P['ankle_y']), 'Shin')
    setm(leg & (y < P['ankle_y']), 'Foot')
    pel = (~leg) & (y < P['waist_y']) & (ax < 2.7)
    setm(pel, 'Pelvis', False)
    # ---- arms (lateral of the torso shell)
    upper = (y >= P['elbow_y']) & (y < P['pad_y']) & (ax > P['arm_x'])
    fore = (y >= P['wrist_y']) & (y < P['elbow_y']) & (ax > P['forearm_x'])
    hand = (y < P['wrist_y']) & (y > 8.0) & (ax > P['hand_x'])
    setm(upper, 'UpperArm')
    setm(fore, 'Forearm')
    setm(hand, 'Hand')
    # ---- shoulder pads: dark armour above the arm, outside the torso notch at |x| 1.85;
    #      plus the pad's lower outer tip that hangs past the arm (|x| > 3.0, y 15.75-16.15)
    pad = (y >= P['pad_y']) & (ax >= P['pad_x']) & (y < 18.2)
    pad |= (y >= 15.75) & (y < P['pad_y']) & (ax > 3.0)
    setm(pad, 'ShoulderPad')
    # ---- head: helmet inside the collar ring, plus the neck block that sits down inside the ring
    r2 = x ** 2 + (z - 0.15) ** 2
    head = (y >= P['neck_y']) & (((y >= 18.45) & (ax < 1.3)) | ((ax < 0.9) & ((r2 < 1.0) | (z < -0.3))))
    head |= (y >= P['neck_block_y']) & (y < P['neck_y']) & (ax < 0.62) & (z > -0.48) & (z < 0.92)
    setm(head, 'Head', False)
    if wing is not None:
        setm(wing, 'Wing')
    return lab


PARTS = ['Head', 'Torso', 'Pelvis', 'Wing_L', 'Wing_R', 'ShoulderPad_L', 'ShoulderPad_R', 'UpperArm_L', 'UpperArm_R',
         'Forearm_L', 'Forearm_R', 'Hand_L', 'Hand_R', 'Thigh_L', 'Thigh_R', 'Shin_L', 'Shin_R', 'Foot_L', 'Foot_R']

COL = {
    'Head': (255, 220, 0), 'Torso': (200, 40, 40), 'Pelvis': (120, 60, 160),
    'Wing_L': (25, 25, 25), 'Wing_R': (25, 25, 25),
    'ShoulderPad_L': (255, 140, 0), 'ShoulderPad_R': (255, 140, 0),
    'UpperArm_L': (40, 120, 220), 'UpperArm_R': (40, 120, 220),
    'Forearm_L': (40, 200, 200), 'Forearm_R': (40, 200, 200),
    'Hand_L': (230, 90, 200), 'Hand_R': (230, 90, 200),
    'Thigh_L': (60, 180, 60), 'Thigh_R': (60, 180, 60),
    'Shin_L': (150, 220, 90), 'Shin_R': (150, 220, 90),
    'Foot_L': (110, 80, 50), 'Foot_R': (110, 80, 50),
}
