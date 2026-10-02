import numpy as np

# cut parameters (studs, model space: +X = mech right, front = -Z, feet y=0)
P = dict(
    neck_y=17.9, head_x=1.75,
    pad_y=17.45, pad_xin=1.75,
    arm_x_top=4.35,   # |X| beyond this (above elbow) is arm
    elbow_y=13.85, wrist_y=9.95,
    waist_y=13.9, waist_x=3.6, hipband_y=12.9, crotch_x=0.95,
    knee_y=7.7, ankle_y=1.85,
)


def label_points(p):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    side = np.where(x >= 0, 'R', 'L')
    lab = np.full(len(p), 'Torso', dtype=object)

    def setm(m, name, sided=True):
        if sided:
            lab[m & (x >= 0)] = name + '_R'
            lab[m & (x < 0)] = name + '_L'
        else:
            lab[m] = name

    # legs: below waist band and lateral of crotch
    leg = (y < P['hipband_y']) & ((ax > P['crotch_x']) | (y < 9.3))
    setm(leg & (y >= P['knee_y']), 'Thigh')
    setm(leg & (y < P['knee_y']) & (y >= P['ankle_y']), 'Shin')
    setm(leg & (y < P['ankle_y']), 'Foot')
    pel = (~leg) & (y < P['waist_y']) & (ax < P['waist_x'])
    setm(pel, 'Pelvis', False)
    # arms: lateral of the torso. The shoulder gear discs (|X| < 4.85, y 15.3-17.9) stay on the torso as sockets.
    arm = (y >= P['elbow_y']) & (y < 16.1) & (ax > 4.0)
    arm |= (y >= 16.1) & (y < 18.25) & (ax > 4.85)
    arm |= (y >= P['wrist_y']) & (y < P['elbow_y']) & (ax > 4.6)
    hand = (y >= 6.5) & (y < P['wrist_y']) & (ax > 5.3)
    setm(arm & (y >= P['elbow_y']), 'UpperArm')
    setm(arm & (y < P['elbow_y']), 'Forearm')
    setm(hand, 'Hand')
    # shoulder pads: the top plates
    pad = (y >= P['pad_y']) & (ax >= P['pad_xin']) & ~arm
    setm(pad, 'ShoulderPad')
    head = (y >= P['neck_y']) & (ax < P['head_x'])
    setm(head, 'Head', False)
    return lab


PARTS = ['Head', 'Torso', 'Pelvis', 'ShoulderPad_L', 'ShoulderPad_R', 'UpperArm_L', 'UpperArm_R',
         'Forearm_L', 'Forearm_R', 'Hand_L', 'Hand_R', 'Thigh_L', 'Thigh_R', 'Shin_L', 'Shin_R', 'Foot_L', 'Foot_R']

COL = {
    'Head': (255, 220, 0), 'Torso': (200, 40, 40), 'Pelvis': (120, 60, 160),
    'ShoulderPad_L': (255, 140, 0), 'ShoulderPad_R': (255, 140, 0),
    'UpperArm_L': (40, 120, 220), 'UpperArm_R': (40, 120, 220),
    'Forearm_L': (40, 200, 200), 'Forearm_R': (40, 200, 200),
    'Hand_L': (230, 90, 200), 'Hand_R': (230, 90, 200),
    'Thigh_L': (60, 180, 60), 'Thigh_R': (60, 180, 60),
    'Shin_L': (150, 220, 90), 'Shin_R': (150, 220, 90),
    'Foot_L': (110, 80, 50), 'Foot_R': (110, 80, 50),
}
