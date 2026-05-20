import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

/// DLNA/投屏设备
class CastDevice {
  String id;
  String name;
  String host;
  int port;
  String? location; // 设备描述URL
  String? iconUrl;
  bool isConnected;
  
  CastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.location,
    this.iconUrl,
    this.isConnected = false,
  });
}

/// 投屏服务
/// 
/// 使用 mDNS (Bonsoir) 发现 DLNA/UPnP 设备
/// 支持 Chromecast、智能电视、投屏器等
class CastService extends ChangeNotifier {
  BonsoirDiscovery? _discovery;
  final List<CastDevice> _devices = [];
  bool _isScanning = false;
  CastDevice? _connectedDevice;
  
  // Dio 用于发送 DLNA 控制请求
  final Dio _dio = Dio();
  
  List<CastDevice> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;
  CastDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;
  
  /// 开始扫描设备
  Future<void> startDiscovery() async {
    if (_isScanning) return;
    
    _isScanning = true;
    _devices.clear();
    notifyListeners();
    
    try {
      // 扫描 DLNA/UPnP 设备 (_services._dns-sd._udp)
      _discovery = BonsoirDiscovery(type: '_http._tcp');
      await _discovery!.ready;
      
      _discovery!.eventStream!.listen((event) async {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          final service = event.service!;
          
          // 解析服务信息 - 从 attributes 获取主机信息
          final attributes = service.attributes;
          String host = '';
          if (attributes.containsKey('host')) {
            host = attributes['host']!;
          }
          
          final device = CastDevice(
            id: '${service.name}_$host',
            name: service.name,
            host: host,
            port: service.port,
          );
          
          // 检查是否是媒体设备
          if (_isMediaDevice(service.name)) {
            _devices.add(device);
            notifyListeners();
            
            // 尝试获取设备详细信息
            if (device.host.isNotEmpty) {
              _fetchDeviceDetails(device);
            }
          }
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
          final service = event.service!;
          final host = service.attributes['host'] ?? '';
          _devices.removeWhere((d) => d.id == '${service.name}_$host');
          notifyListeners();
        }
      });
      
      await _discovery!.start();
      
      // 同时扫描特定服务类型
      await _scanDLNAServices();
      
    } catch (e) {
      debugPrint('设备扫描错误: $e');
    }
  }
  
  /// 停止扫描
  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
    }
    _isScanning = false;
    notifyListeners();
  }
  
  /// 检查是否是媒体设备
  bool _isMediaDevice(String name) {
    final lower = name.toLowerCase();
    final keywords = [
      'tv', '电视', 'chromecast', 'dlna', 'upnp', 'media',
      'renderer', '播放器', '小米', 'xiao', 'huawei', '华为',
      'sony', 'samsung', 'lg', 'panasonic', 'philips',
    ];
    return keywords.any((k) => lower.contains(k));
  }
  
  /// 扫描 DLNA 特定服务
  Future<void> _scanDLNAServices() async {
    final discoveryTypes = [
      '_upnp._tcp',
      '_dlna._tcp',
      '_googlecast._tcp',
    ];
    
    for (final type in discoveryTypes) {
      try {
        final discovery = BonsoirDiscovery(type: type);
        await discovery.ready;
        
        discovery.eventStream!.listen((event) {
          if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
            final service = event.service!;
            final host = service.attributes['host'] ?? '';
            final device = CastDevice(
              id: '${service.name}_$host',
              name: service.name,
              host: host,
              port: service.port,
            );
            
            if (!_devices.any((d) => d.id == device.id)) {
              _devices.add(device);
              notifyListeners();
            }
          }
        });
        
        await discovery.start();
        
        // 5秒后停止这个发现
        Future.delayed(const Duration(seconds: 5), () => discovery.stop());
      } catch (e) {
        debugPrint('DLNA扫描错误 ($type): $e');
      }
    }
  }
  
  /// 获取设备详细信息
  Future<void> _fetchDeviceDetails(CastDevice device) async {
    try {
      // 常见 UPnP 设备描述路径
      final paths = [
        '/rootDesc.xml',
        '/dmr',
        '/description.xml',
        '/DeviceDescription.xml',
      ];
      
      for (final path in paths) {
        try {
          final response = await _dio.get(
            'http://${device.host}:${device.port}$path',
            options: Options(
              sendTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
            ),
          );
          
          if (response.statusCode == 200) {
            final xmlDoc = XmlDocument.parse(response.data);
            
            // 提取设备名称
            final friendlyName = xmlDoc.findAllElements('friendlyName').firstOrNull?.value;
            if (friendlyName != null && friendlyName.isNotEmpty) {
              device.name = friendlyName;
            }
            
            // 提取图标
            final iconUrl = xmlDoc.findAllElements('icon').firstOrNull?.findElements('url').firstOrNull?.value;
            if (iconUrl != null) {
              device.iconUrl = 'http://${device.host}:${device.port}$iconUrl';
            }
            
            device.location = 'http://${device.host}:${device.port}$path';
            notifyListeners();
            break;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('获取设备详情失败: $e');
    }
  }
  
  /// 连接设备
  Future<bool> connect(CastDevice device) async {
    try {
      // 测试连接
      await _dio.get(
        'http://${device.host}:${device.port}',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      
      _connectedDevice = device;
      device.isConnected = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('连接设备失败: $e');
      return false;
    }
  }
  
  /// 断开连接
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      _connectedDevice!.isConnected = false;
      _connectedDevice = null;
      notifyListeners();
    }
  }
  
  /// 投屏播放
  Future<bool> castVideo(String videoUrl, {String? title}) async {
    if (_connectedDevice == null) return false;
    
    try {
      // DLNA SetAVTransportURI 动作
      final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>${Uri.encodeFull(videoUrl)}</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';      
      await _dio.post(
        'http://${_connectedDevice!.host}:${_connectedDevice!.port}/MediaRenderer/AVTransport/Control',
        data: soapBody,
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
          },
        ),
      );
      
      // 发送播放命令
      const playBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>''';
      
      await _dio.post(
        'http://${_connectedDevice!.host}:${_connectedDevice!.port}/MediaRenderer/AVTransport/Control',
        data: playBody,
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
          },
        ),
      );
      
      return true;
    } catch (e) {
      debugPrint('投屏失败: $e');
      return false;
    }
  }
  
  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}
