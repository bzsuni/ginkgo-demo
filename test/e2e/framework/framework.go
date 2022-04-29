// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Spiderpool

package framework

import (
	"context"
	"fmt"
	"os"
	"time"

	nettypes "github.com/k8snetworkplumbingwg/network-attachment-definition-client/pkg/apis/k8s.cni.cncf.io/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/klog/v2"

	netclient "github.com/k8snetworkplumbingwg/network-attachment-definition-client/pkg/client/clientset/versioned/typed/k8s.cni.cncf.io/v1"
)

const (
	createTimeout = 30 * time.Second
	deleteTimeout = 2 * createTimeout
)

type Framework struct {
	BaseName        string
	SystemNameSpace string
	KubeClientSet   *kubernetes.Clientset
	KubeConfig      *rest.Config
	NetClientSet    netclient.K8sCniCncfIoV1Interface
}

// NewFramework init Framework struct
func NewFramework(baseName string) *Framework {
	f := &Framework{BaseName: baseName}

	kubeconfigPath := fmt.Sprintf("%s/.kube/config", os.Getenv("HOME"))
	cfg, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		klog.Fatal(err)
	}
	f.KubeConfig = cfg

	cfg.QPS = 1000
	cfg.Burst = 2000
	kubeClient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		klog.Fatal(err)
	}
	netClient, err := netclient.NewForConfig(cfg)
	if err != nil {
		klog.Fatal(err)
	}
	f.KubeClientSet = kubeClient
	f.NetClientSet = netClient

	return f
}

func (f *Framework) AddNetAttachDef(netattach *nettypes.NetworkAttachmentDefinition) (*nettypes.NetworkAttachmentDefinition, error) {
	return f.NetClientSet.NetworkAttachmentDefinitions(netattach.ObjectMeta.Namespace).Create(context.TODO(), netattach, metav1.CreateOptions{})
}

func (f *Framework) DelNetAttachDef(netattach *nettypes.NetworkAttachmentDefinition) error {
	return f.NetClientSet.NetworkAttachmentDefinitions(netattach.ObjectMeta.Namespace).Delete(context.TODO(), netattach.Name, metav1.DeleteOptions{})
}

func (f *Framework) CreatePod(podNamespace, podName, image string, label, annotations map[string]string) (*corev1.Pod, error) {
	pod := podObject(podNamespace, podName, image, label, annotations)
	pod, err := f.KubeClientSet.CoreV1().Pods(pod.Namespace).Create(context.Background(), pod, metav1.CreateOptions{})
	if err != nil {
		return nil, err
	}

	if err := WaitForPodReady(f.KubeClientSet, pod.Namespace, pod.Name, createTimeout); err != nil {
		return nil, err
	}

	pod, err = f.KubeClientSet.CoreV1().Pods(pod.Namespace).Get(context.Background(), pod.Name, metav1.GetOptions{})
	if err != nil {
		return nil, err
	}

	return pod, nil
}

func (f *Framework) DeletePod(pod *corev1.Pod) error {
	if err := f.KubeClientSet.CoreV1().Pods(pod.Namespace).Delete(context.TODO(), pod.Name, metav1.DeleteOptions{}); err != nil {
		return err
	}

	if err := WaitForPodToDisappear(f.KubeClientSet, pod.GetNamespace(), pod.GetName(), deleteTimeout); err != nil {
		return err
	}
	return nil
}

func podObject(podNamespace, podName, image string, label, annotations map[string]string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:        podName,
			Namespace:   podNamespace,
			Labels:      label,
			Annotations: annotations,
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{
				{
					Name:            "samplepod",
					Command:         containerCmd(),
					Image:           image,
					ImagePullPolicy: "IfNotPresent",
				},
			},
		},
	}
}

func containerCmd() []string {
	return []string{"/bin/sh", "-c", "trap : TERM INT; sleep infinity & wait"}
}
