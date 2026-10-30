// Generated protocol metadata: wlr-output-management v4. See PROTOCOL_LICENSE.md.
use crate::wayland::{Interface, Message, Types};
use std::ptr;
static ZWLR_OUTPUT_MANAGER_V1_REQUEST_0_T: Types<2> =
    Types([&ZWLR_OUTPUT_CONFIGURATION_V1, ptr::null()]);
static ZWLR_OUTPUT_MANAGER_V1_REQUEST_1_T: Types<0> = Types([]);
static ZWLR_OUTPUT_MANAGER_V1_REQUEST: [Message; 2] = [
    Message {
        name: c"create_configuration".as_ptr(),
        signature: c"nu".as_ptr(),
        types: ZWLR_OUTPUT_MANAGER_V1_REQUEST_0_T.0.as_ptr(),
    },
    Message {
        name: c"stop".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_MANAGER_V1_REQUEST_1_T.0.as_ptr(),
    },
];
static ZWLR_OUTPUT_MANAGER_V1_EVENT_0_T: Types<1> = Types([&ZWLR_OUTPUT_HEAD_V1]);
static ZWLR_OUTPUT_MANAGER_V1_EVENT_1_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_MANAGER_V1_EVENT_2_T: Types<0> = Types([]);
static ZWLR_OUTPUT_MANAGER_V1_EVENT: [Message; 3] = [
    Message {
        name: c"head".as_ptr(),
        signature: c"n".as_ptr(),
        types: ZWLR_OUTPUT_MANAGER_V1_EVENT_0_T.0.as_ptr(),
    },
    Message {
        name: c"done".as_ptr(),
        signature: c"u".as_ptr(),
        types: ZWLR_OUTPUT_MANAGER_V1_EVENT_1_T.0.as_ptr(),
    },
    Message {
        name: c"finished".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_MANAGER_V1_EVENT_2_T.0.as_ptr(),
    },
];
pub static ZWLR_OUTPUT_MANAGER_V1: Interface = Interface {
    name: c"zwlr_output_manager_v1".as_ptr(),
    version: 4,
    method_count: 2,
    methods: ZWLR_OUTPUT_MANAGER_V1_REQUEST.as_ptr(),
    event_count: 3,
    events: ZWLR_OUTPUT_MANAGER_V1_EVENT.as_ptr(),
};
static ZWLR_OUTPUT_HEAD_V1_REQUEST_0_T: Types<0> = Types([]);
static ZWLR_OUTPUT_HEAD_V1_REQUEST: [Message; 1] = [Message {
    name: c"release".as_ptr(),
    signature: c"3".as_ptr(),
    types: ZWLR_OUTPUT_HEAD_V1_REQUEST_0_T.0.as_ptr(),
}];
static ZWLR_OUTPUT_HEAD_V1_EVENT_0_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_1_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_2_T: Types<2> = Types([ptr::null(), ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_3_T: Types<1> = Types([&ZWLR_OUTPUT_MODE_V1]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_4_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_5_T: Types<1> = Types([&ZWLR_OUTPUT_MODE_V1]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_6_T: Types<2> = Types([ptr::null(), ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_7_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_8_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_9_T: Types<0> = Types([]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_10_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_11_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_12_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT_13_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_HEAD_V1_EVENT: [Message; 14] = [
    Message {
        name: c"name".as_ptr(),
        signature: c"s".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_0_T.0.as_ptr(),
    },
    Message {
        name: c"description".as_ptr(),
        signature: c"s".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_1_T.0.as_ptr(),
    },
    Message {
        name: c"physical_size".as_ptr(),
        signature: c"ii".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_2_T.0.as_ptr(),
    },
    Message {
        name: c"mode".as_ptr(),
        signature: c"n".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_3_T.0.as_ptr(),
    },
    Message {
        name: c"enabled".as_ptr(),
        signature: c"i".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_4_T.0.as_ptr(),
    },
    Message {
        name: c"current_mode".as_ptr(),
        signature: c"o".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_5_T.0.as_ptr(),
    },
    Message {
        name: c"position".as_ptr(),
        signature: c"ii".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_6_T.0.as_ptr(),
    },
    Message {
        name: c"transform".as_ptr(),
        signature: c"i".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_7_T.0.as_ptr(),
    },
    Message {
        name: c"scale".as_ptr(),
        signature: c"f".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_8_T.0.as_ptr(),
    },
    Message {
        name: c"finished".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_9_T.0.as_ptr(),
    },
    Message {
        name: c"make".as_ptr(),
        signature: c"2s".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_10_T.0.as_ptr(),
    },
    Message {
        name: c"model".as_ptr(),
        signature: c"2s".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_11_T.0.as_ptr(),
    },
    Message {
        name: c"serial_number".as_ptr(),
        signature: c"2s".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_12_T.0.as_ptr(),
    },
    Message {
        name: c"adaptive_sync".as_ptr(),
        signature: c"4u".as_ptr(),
        types: ZWLR_OUTPUT_HEAD_V1_EVENT_13_T.0.as_ptr(),
    },
];
pub static ZWLR_OUTPUT_HEAD_V1: Interface = Interface {
    name: c"zwlr_output_head_v1".as_ptr(),
    version: 4,
    method_count: 1,
    methods: ZWLR_OUTPUT_HEAD_V1_REQUEST.as_ptr(),
    event_count: 14,
    events: ZWLR_OUTPUT_HEAD_V1_EVENT.as_ptr(),
};
static ZWLR_OUTPUT_MODE_V1_REQUEST_0_T: Types<0> = Types([]);
static ZWLR_OUTPUT_MODE_V1_REQUEST: [Message; 1] = [Message {
    name: c"release".as_ptr(),
    signature: c"3".as_ptr(),
    types: ZWLR_OUTPUT_MODE_V1_REQUEST_0_T.0.as_ptr(),
}];
static ZWLR_OUTPUT_MODE_V1_EVENT_0_T: Types<2> = Types([ptr::null(), ptr::null()]);
static ZWLR_OUTPUT_MODE_V1_EVENT_1_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_MODE_V1_EVENT_2_T: Types<0> = Types([]);
static ZWLR_OUTPUT_MODE_V1_EVENT_3_T: Types<0> = Types([]);
static ZWLR_OUTPUT_MODE_V1_EVENT: [Message; 4] = [
    Message {
        name: c"size".as_ptr(),
        signature: c"ii".as_ptr(),
        types: ZWLR_OUTPUT_MODE_V1_EVENT_0_T.0.as_ptr(),
    },
    Message {
        name: c"refresh".as_ptr(),
        signature: c"i".as_ptr(),
        types: ZWLR_OUTPUT_MODE_V1_EVENT_1_T.0.as_ptr(),
    },
    Message {
        name: c"preferred".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_MODE_V1_EVENT_2_T.0.as_ptr(),
    },
    Message {
        name: c"finished".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_MODE_V1_EVENT_3_T.0.as_ptr(),
    },
];
pub static ZWLR_OUTPUT_MODE_V1: Interface = Interface {
    name: c"zwlr_output_mode_v1".as_ptr(),
    version: 3,
    method_count: 1,
    methods: ZWLR_OUTPUT_MODE_V1_REQUEST.as_ptr(),
    event_count: 4,
    events: ZWLR_OUTPUT_MODE_V1_EVENT.as_ptr(),
};
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_0_T: Types<2> =
    Types([&ZWLR_OUTPUT_CONFIGURATION_HEAD_V1, &ZWLR_OUTPUT_HEAD_V1]);
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_1_T: Types<1> = Types([&ZWLR_OUTPUT_HEAD_V1]);
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_2_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_3_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_4_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST: [Message; 5] = [
    Message {
        name: c"enable_head".as_ptr(),
        signature: c"no".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_0_T.0.as_ptr(),
    },
    Message {
        name: c"disable_head".as_ptr(),
        signature: c"o".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_1_T.0.as_ptr(),
    },
    Message {
        name: c"apply".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_2_T.0.as_ptr(),
    },
    Message {
        name: c"test".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_3_T.0.as_ptr(),
    },
    Message {
        name: c"destroy".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST_4_T.0.as_ptr(),
    },
];
static ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_0_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_1_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_2_T: Types<0> = Types([]);
static ZWLR_OUTPUT_CONFIGURATION_V1_EVENT: [Message; 3] = [
    Message {
        name: c"succeeded".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_0_T.0.as_ptr(),
    },
    Message {
        name: c"failed".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_1_T.0.as_ptr(),
    },
    Message {
        name: c"cancelled".as_ptr(),
        signature: c"".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_V1_EVENT_2_T.0.as_ptr(),
    },
];
pub static ZWLR_OUTPUT_CONFIGURATION_V1: Interface = Interface {
    name: c"zwlr_output_configuration_v1".as_ptr(),
    version: 4,
    method_count: 5,
    methods: ZWLR_OUTPUT_CONFIGURATION_V1_REQUEST.as_ptr(),
    event_count: 3,
    events: ZWLR_OUTPUT_CONFIGURATION_V1_EVENT.as_ptr(),
};
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_0_T: Types<1> = Types([&ZWLR_OUTPUT_MODE_V1]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_1_T: Types<3> =
    Types([ptr::null(), ptr::null(), ptr::null()]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_2_T: Types<2> = Types([ptr::null(), ptr::null()]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_3_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_4_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_5_T: Types<1> = Types([ptr::null()]);
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST: [Message; 6] = [
    Message {
        name: c"set_mode".as_ptr(),
        signature: c"o".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_0_T.0.as_ptr(),
    },
    Message {
        name: c"set_custom_mode".as_ptr(),
        signature: c"iii".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_1_T.0.as_ptr(),
    },
    Message {
        name: c"set_position".as_ptr(),
        signature: c"ii".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_2_T.0.as_ptr(),
    },
    Message {
        name: c"set_transform".as_ptr(),
        signature: c"i".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_3_T.0.as_ptr(),
    },
    Message {
        name: c"set_scale".as_ptr(),
        signature: c"f".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_4_T.0.as_ptr(),
    },
    Message {
        name: c"set_adaptive_sync".as_ptr(),
        signature: c"4u".as_ptr(),
        types: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST_5_T.0.as_ptr(),
    },
];
static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_EVENT: [Message; 0] = [];
pub static ZWLR_OUTPUT_CONFIGURATION_HEAD_V1: Interface = Interface {
    name: c"zwlr_output_configuration_head_v1".as_ptr(),
    version: 4,
    method_count: 6,
    methods: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_REQUEST.as_ptr(),
    event_count: 0,
    events: ZWLR_OUTPUT_CONFIGURATION_HEAD_V1_EVENT.as_ptr(),
};
