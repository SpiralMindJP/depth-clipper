//
//  CameraView.swift
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

import SwiftUI

public struct CameraView: View {
    @State var confidenceThreshold = RendererParams.defaultConfidenceThreshold
    @State var mode: CaptureMode = .trueDepth
    @State var nearDepthThreshold = RendererParams.defaultNearDepthThreshold
    @State var farDepthThreshold = RendererParams.defaultFarDepthThreshold

    public init() {
    }

    public var body: some View {
        ZStack {
            if self.mode == .lidar {
                CameraViewControllerWrapper(mode: self.mode, confidenceThreshold: self.confidenceThreshold, nearDepthThreshold: self.nearDepthThreshold, farDepthThreshold: self.farDepthThreshold)
                    .ignoresSafeArea()
            } else if self.mode == .trueDepth {
                CameraViewControllerWrapper(mode: self.mode, confidenceThreshold: self.confidenceThreshold, nearDepthThreshold: self.nearDepthThreshold, farDepthThreshold: self.farDepthThreshold)
                    .ignoresSafeArea()
            }

            VStack(alignment: .center) {
                Picker("Capture Mode", selection: $mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text("\(mode)".capitalized)
                            .tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                Spacer()
            }
            .frame(width: 300, height: nil, alignment: .center)
            .padding()

            VStack(alignment: .center, spacing: 20) {
                Spacer()

                Slider(value: $nearDepthThreshold, in: RendererParams.minDepthThreshold...farDepthThreshold)
                Slider(value: $farDepthThreshold, in: nearDepthThreshold...RendererParams.maxDepthThreshold)
            }
            .frame(width: 300, height: nil, alignment: .center)
            .padding()
        }
    }
}

struct CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}
