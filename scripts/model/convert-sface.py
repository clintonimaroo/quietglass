"""Reproduce the bundled model and compare Core ML with the pinned ONNX weights.

Run in an isolated Python environment with requirements.txt. No face images needed.
"""
import argparse
import hashlib
import json
import pathlib
import urllib.request

import coremltools as ct
import numpy as np
import onnx
import onnxruntime as ort
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

REVISION = "47534e27c9851bb1128ccc0102f1145e27f23f98"
SOURCE_SHA256 = "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
URL = f"https://media.githubusercontent.com/media/opencv/opencv_zoo/{REVISION}/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"


def convert(source, destination):
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Model checksum does not match the pinned SFace weights")
    graph = onnx.load(source).graph
    weights = {w.name: onnx.numpy_helper.to_array(w) for w in graph.initializer}
    builder = NeuralNetworkBuilder([("data", datatypes.Array(3, 112, 112))], [("fc1", datatypes.Array(128))])
    aliases = {}
    for node in graph.node:
        a = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
        name, ins, out = node.name, list(node.input), node.output[0]
        inp = aliases.get(ins[0], ins[0])
        if node.op_type in ("Sub", "Mul"):
            scalar = weights[ins[1]].ravel()
            builder.add_scale(name, np.ones(1) if node.op_type == "Sub" else scalar,
                              -scalar if node.op_type == "Sub" else np.zeros(1), True, inp, out,
                              shape_scale=[1], shape_bias=[1])
        elif node.op_type == "Conv":
            w = weights[ins[1]]
            p = a["pads"]
            builder.add_convolution(name, w.shape[1], w.shape[0], w.shape[2], w.shape[3],
                                    a["strides"][0], a["strides"][1], "valid", a["group"],
                                    w.transpose(2, 3, 1, 0), None, False, input_name=inp, output_name=out,
                                    padding_top=p[0], padding_left=p[1], padding_bottom=p[2], padding_right=p[3])
        elif node.op_type == "BatchNormalization":
            gamma, beta, mean, var = [weights[i] for i in ins[1:]]
            builder.add_batchnorm(name, gamma.size, gamma, beta, mean, var, inp, out, epsilon=a["epsilon"])
        elif node.op_type == "PRelu":
            builder.add_activation(name, "PRELU", inp, out, params=weights[ins[1]].ravel())
        elif node.op_type == "Dropout":
            aliases[out] = inp
        elif node.op_type == "Flatten":
            builder.add_flatten(name, 0, inp, out)
        elif node.op_type == "Gemm":
            assert a == {"alpha": 1.0, "beta": 1.0, "transA": 0, "transB": 1}
            w = weights[ins[1]]
            builder.add_inner_product(name, w, weights[ins[2]], w.shape[1], w.shape[0], True, inp, out)
        else:
            raise ValueError(f"Unsupported operator: {node.op_type}")
    model = ct.models.MLModel(builder.spec, compute_units=ct.ComputeUnit.CPU_ONLY)
    model.author = "OpenCV Zoo / SFace authors; Core ML conversion for QuietGlass"
    model.license = "Apache-2.0; see Resources/Models/SFace-LICENSE.txt"
    model.short_description = "SFace 2021dec. Aligned 112x112 RGB, raw 0-255 CHW. Output: 128 unnormalized floats."
    model.user_defined_metadata["source_revision"] = REVISION
    model.user_defined_metadata["source_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
    model.save(str(destination))
    # Initializers are not runtime inputs; removing them avoids ORT's legacy warnings.
    m = onnx.load(source)
    runtime_inputs = [i for i in m.graph.input if i.name not in weights]
    del m.graph.input[:]
    m.graph.input.extend(runtime_inputs)
    session = ort.InferenceSession(m.SerializeToString(), providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(20260921)
    checks = []
    for name, data in [("black", np.zeros((3, 112, 112), np.float32)),
                       ("white", np.full((3, 112, 112), 255, np.float32)),
                       ("noise", rng.uniform(0, 255, (3, 112, 112)).astype(np.float32)),
                       ("ramp", np.linspace(0, 255, 3 * 112 * 112, dtype=np.float32).reshape(3, 112, 112))]:
        expected = session.run(None, {"data": data[None]})[0].ravel()
        actual = model.predict({"data": data})["fc1"].ravel()
        cosine = float(np.dot(expected, actual) / (np.linalg.norm(expected) * np.linalg.norm(actual)))
        assert np.isfinite(actual).all() and cosine > 0.99999, (name, cosine)
        checks.append({"input": name, "cosine": cosine, "max_absolute_error": float(np.max(np.abs(expected-actual)))})
    return {"revision": REVISION, "onnx_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "coreml_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "checks": checks}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--onnx", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--report", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if not args.onnx.exists():
        args.onnx.parent.mkdir(parents=True, exist_ok=True)
        args.onnx.write_bytes(urllib.request.urlopen(URL).read())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = convert(args.onnx, args.output)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
